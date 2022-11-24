use v5.10;
use strict;
use warnings;

use Encode;
use File::Spec;
use FindBin;
use Getopt::Long;
use IPC::Cmd;
use Time::HiRes qw(gettimeofday);

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::Backup;
use CATS::Config;
use CATS::DB;
use CATS::Mail;
use CATS::Utils qw(group_digits);

sub usage {
    print STDERR "CATS Backup tool
Usage: $0 <options>
Options:
$CATS::Backup::options
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

my $prefix = 'cats-';

sub work {
    printf "DBI: %s\nHost: %s\nDatabase: %s\n\n",
        $db->{driver}, $db->{host}, $db->{name} if !$quiet;

    -d $dest or die "Bad destination: $dest";

    my $file = CATS::Backup::find_file(
        $dest, $prefix, $zip, $db->{driver} =~ /Firebird/ ? '.fbk' : '.sql', 'gz');
    print "Destination: $file\n" if !$quiet;

    my ($cmd, $ok, $err, $full);
    if ($db->{driver} =~ /Firebird/) {
        IPC::Cmd::can_run('gbak') or die 'Error: gbak not found';

        ($ok, $err, $full) = IPC::Cmd::run command => [ 'gbak', '-Z' ];
        # Given -Z, gbak exits with 1 instead of 0.
        $ok || $err =~ /value 1/ or die "Error running gbak: $err";

        $full && "@$full" =~ /gbak:\s*gbak version/ or die "Error: gbak not correct: @$full";

        $cmd = [ 'gbak', '-B', "$db->{host}:$db->{name}", $file, 
            '-USER', $db->{user}, '-PAS', $db->{password}, '-RO', 'RDB$ADMIN' ];
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
        open my $f, '>', $file or die $!;
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
    my $result_time = sprintf "Backup time: %s\n", CATS::Backup::fmt_interval($start_ts, $backup_ts);

    if ($zip) {
        ($ok, $err, $full) = IPC::Cmd::run command => [ 'gzip', '-q', $file ];
        $ok or die join "\n", $err, @$full;
        my $compressed_size = group_digits(-s "$file.gz", '_');
        $result .= "Zipped: $compressed_size\n";
        my $zip_ts = [ gettimeofday ];
        $result_time .= sprintf "Zip time: %s\n", CATS::Backup::fmt_interval($backup_ts, $zip_ts);
        $file .= '.gz';
    }
    CATS::Backup::maybe_chown($chown, $file, $quiet);
    $result .= CATS::Backup::remove_old_backup($dest, $prefix, $max, $quiet) // '' if $max;
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
