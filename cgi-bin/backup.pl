use strict;
use warnings;

use Encode;
use File::Spec;
use Getopt::Long;
use IPC::Cmd;
use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday);

use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1], 'cats-problem');
use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1]);

use CATS::Config;
use CATS::DB;
use CATS::Mail;

sub usage {
    print STDERR "CATS Backup tool
Usage: $0 <options>
Options:
  [--help]\t\tDisplay this help.
  --report={std|mail}\tPrint report to stdout or send it by email.
  [--quiet]\t\tDo not print progress info.
  [--dest=<path>]\tStore backups in a given folder, default is '../ib_data'.
  [--zip]\t\tCompress backup.
  [--chown=<user>]\tChange backup file ownership.
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
    imitate => \(my $imitate = 0),
) or usage;

usage if $help;

if (!$report || $report !~ /^(std|mail)$/) {
    print STDERR "Wrong or missing --report option\n";
    usage;
}

$dest ||= File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1], '..', 'ib_data');

sub fmt_interval {
    my $s = Time::HiRes::tv_interval(@_);
    my $ms = int(1000 * ($s - int($s)));
    my $m = int($s / 60);
    $s %= 60;
    sprintf '%02d:%02d.%03d', $m, $s, $ms;
}

sub work {
    IPC::Cmd::can_run('gbak') or die 'Error: gbak not found';

    my ($ok, $err, $full) = IPC::Cmd::run command => [ 'gbak', '-Z' ];
    # Given -Z, gbak exits with 1 instead of 0.
    $ok || $err =~ /value 1/ or die "Error running gbak: $err";

    $full && $full->[0] =~ /gbak:gbak version/ or die "Error: gbak not correct: $full->[0]";

    my ($db, $host) = $CATS::Config::db_dsn =~ /dbname=(\S+?);host=(\S+?);/
        or die "Bad config DSN: $CATS::Config::db_dsn";
    print "Host: $host\nDatabase: $db\n" if !$quiet;

    -d $dest or die "Bad destination: $dest";

    my $file;
    for (my $i = 0; $i < 10; ++$i) {
        my $n = File::Spec->catfile($dest, strftime('cats-%Y-%m-%d', localtime) . ($i ? "-$i" : '') . '.fbk');
        next if -f $n;
        next if -f "$n.gz" && $zip;
        $file = $n;
        last;
    }
    $file or die "Too many backups at $dest";

    print "Destination: $file\n" if !$quiet;
    my $cmd = [ 'gbak', '-B', "$host:$db", $file,
        '-USER', $CATS::Config::db_user, '-PAS', $CATS::Config::db_password ];

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
    my $uncompressed_size = -s $file;
    my $result = "File: $file\nSize: $uncompressed_size\n";
    my $backup_ts = [ gettimeofday ];
    my $result_time = sprintf "Backup time: %s\n", fmt_interval($start_ts, $backup_ts);

    if ($zip) {
        ($ok, $err, $full) = IPC::Cmd::run command => [ 'gzip', '-q', $file ];
        $ok or die join "\n", $err, @$full;
        my $compressed_size = -s "$file.gz";
        $result .= "Zipped: $compressed_size\n";
        my $zip_ts = [ gettimeofday ];
        $result_time .= sprintf "Zip time: %s\n", fmt_interval($backup_ts, $zip_ts);
        $file .= '.gz';
    }
    if ($chown) {
        print "chown $chown:$chown $file\n" if !$quiet;
        my (undef, undef, $uid, $gid) = getpwnam($chown) or die "User nod found: $chown";
        chown $uid, $gid, $file or die "Error: chown: $!";
    }
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
