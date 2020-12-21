use v5.10;
use strict;
use warnings;

use Encode;
use File::Spec;
use File::stat;
use FindBin;
use Getopt::Long;
use IPC::Cmd;
use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday);

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::Config;
use CATS::DB;
use CATS::Mail;
use CATS::Utils qw(group_digits);

sub usage {
    print STDERR "CATS Backup tool
Usage: $0 <options>
Options:
  [--help]\t\tDisplay this help.
  --report={std|mail}\tPrint report to stdout or send it by email.
  [--quiet]\t\tDo not print progress info.
  [--dest=<path>]\tStore backups in a given folder, default is '../backups'.
  [--zip]\t\tCompress backup.
  [--chown=<user>]\tChange backup file ownership.
  [--max=<number>]\tRemove oldest backup when maximum count is reached.
  [--imitate]\t\tCreate dummy backup file for testing.
";
    exit;
}

GetOptions(
    help => \(my $help = 0),
    'report=s' => \(my $report = ''),
    quiet => \(my $quiet = 0),
    'dest=s' => \(my $dest),
    zip => \(my $zip = 0),
    'chown=s' => \(my $chown = 0),
    'max=i' => \(my $max),
    imitate => \(my $imitate = 0),
) or usage;

usage if $help;

if (!$report || $report !~ /^(std|mail)$/) {
    print STDERR "Wrong or missing --report option\n";
    usage;
}

my $db = $CATS::Config::db;
$dest ||= File::Spec->catdir($FindBin::Bin, '..', 'backups');

sub fmt_interval {
    my $s = Time::HiRes::tv_interval(@_);
    my $ms = int(1000 * ($s - int($s)));
    my $m = int($s / 60);
    $s %= 60;
    sprintf '%02d:%02d.%03d', $m, $s, $ms;
}

my $prefix = 'cats-';

sub remove_old_backup {
    my @all_backups = glob(File::Spec->catfile($dest, "$prefix*.*"));
    print "Backups total: " . @all_backups . ", max = $max\n" if !$quiet;
    return if $max >=  @all_backups;
    my ($oldest_mtime, $oldest);
    for (@all_backups) {
        my $mtime = stat($_)->mtime;
        next if $oldest_mtime && $mtime > $oldest_mtime;
        $oldest = $_;
        $oldest_mtime = $mtime;
    }
    $oldest or return;
    unlink $oldest or die "Remove error: $!";
    return "Removed: $oldest\n";
}

sub find_file {
    for (my $i = 0; $i < 10; ++$i) {
        my $ext = $db->{driver} =~ /Firebird/ ? '.fbk' : '.sql';
        my $n = File::Spec->catfile($dest,
            $prefix . strftime('%Y-%m-%d', localtime) . ($i ? "-$i" : '') . $ext);
        next if -f $n;
        next if -f "$n.gz" && $zip;
        return $n;
    }
    die "Too many backups at $dest";
}

sub work {
    printf "DBI: %s\nHost: %s\nDatabase: %s\n\n",
        $db->{driver}, $db->{host}, $db->{name} if !$quiet;

    -d $dest or die "Bad destination: $dest";

    my $file = find_file;
    print "Destination: $file\n" if !$quiet;

    my ($cmd, $ok, $err, $full);
    if ($db->{driver} =~ /Firebird/) {
        IPC::Cmd::can_run('gbak') or die 'Error: gbak not found';

        ($ok, $err, $full) = IPC::Cmd::run command => [ 'gbak', '-Z' ];
        # Given -Z, gbak exits with 1 instead of 0.
        $ok || $err =~ /value 1/ or die "Error running gbak: $err";

        $full && "@$full" =~ /gbak:gbak version/ or die "Error: gbak not correct: @$full";

        $cmd = [ 'gbak', '-B', "$db->{host}:$db->{name}", $file, 
            '-USER', $db->{user}, '-PAS', $db->{password} ];
    } elsif ($db->{driver} =~ /Pg/) {
        IPC::Cmd::can_run('pg_dump') or die 'Error: pg_dump not found';

        my $dbname = sprintf "postgresql://%s:%s@%s:5432/%s",
            $db->{user}, $db->{password}, $db->{host}, $db->{name};
        $cmd = [ 'pg_dump', '-f', $file, '--dbname', $dbname ];
    } else {
        die "Unknown driver: '$db->{driver}'";
    }

    my $start_ts = [ gettimeofday ];

    if ($imitate) {
        printf "Command: %s\n", join ' ', @$cmd if !$quiet;
        open my $f, '>', $file;
        print $f 'testtest' x 10;
        $ok = 1;
        $err = 0;
    }
    else {
        ($ok, $err, $full) = IPC::Cmd::run command => $cmd;
    }
    $ok or die join "\n", $err, @$full;
    my $uncompressed_size = group_digits(-s $file, '_');
    my $result = "File: $file\nSize: $uncompressed_size\n";
    my $backup_ts = [ gettimeofday ];
    my $result_time = sprintf "Backup time: %s\n", fmt_interval($start_ts, $backup_ts);

    if ($zip) {
        ($ok, $err, $full) = IPC::Cmd::run command => [ 'gzip', '-q', $file ];
        $ok or die join "\n", $err, @$full;
        my $compressed_size = group_digits(-s "$file.gz", '_');
        $result .= "Zipped: $compressed_size\n";
        my $zip_ts = [ gettimeofday ];
        $result_time .= sprintf "Zip time: %s\n", fmt_interval($backup_ts, $zip_ts);
        $file .= '.gz';
    }
    if ($chown) {
        print "chown $chown:$chown $file\n" if !$quiet;
        my (undef, undef, $uid, $gid) = getpwnam($chown) or die "User not found: $chown";
        chown $uid, $gid, $file or die "Error: chown: $!";
    }
    $result .= remove_old_backup() // '' if $max;
    print "\n" if !$quiet;
    $result . $result_time;
}

my $ok = eval { work; };
my $err = $@;
my $text = sprintf "Subject: CATS Backup Report (%s)\n\n%s\n", $ok ? 'ok' : 'ERROR', $ok // $err;

if ($report eq 'mail') {
    CATS::Mail::send($CATS::Config::health_report_email, $text);
}
else {
    print Encode::encode_utf8($text);
}
