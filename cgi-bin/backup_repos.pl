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
use CATS::Mail;
use CATS::Problem::Repository;
use CATS::Utils qw(group_digits);

sub usage {
    print STDERR "CATS Repository backup tool
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

$dest ||= File::Spec->catdir($FindBin::Bin, '..', 'backups', 'repo');

my $prefix = 'catsr-';

sub work {
    IPC::Cmd::can_run('git') or die 'Error: git not found';

    my ($ok, $err, $full) = IPC::Cmd::run command => [ 'git', '--version' ];
    $ok && $full && $full->[0] =~ /git version/ or die "Error: git not correct: @$full";

    -d $dest or die "Bad destination: $dest";

    my $file = CATS::Backup::find_file($dest, $prefix, $zip, '', 'zip');

    print "Destination: $file\n" if !$quiet;

    my $start_ts = [ gettimeofday ];

    opendir my $repos_dir, $CATS::Config::repos_dir or die $!;
    my @repos = sort { $a <=>$b } grep /^\d+$/, readdir($repos_dir);
    my $result .= sprintf "Total repos: %d\n", scalar(@repos);
    mkdir $file or die "mkdir: $!";
    my $uncompressed_size = 0;

    if ($imitate) {
        printf "Dry run\n" if !$quiet;
        open my $f, '>', File::Spec->catfile($file, 'test.bundle')
            or die Encode::decode_utf8("$!: $file");
        print $f 'testtest' x 10;
    }
    else {
        for (my $index = 0; $index < @repos; ++$index) {
            my $repo_name = $repos[$index];
            printf '%5d: %s', $index, $repo_name if !$quiet;
            my $repo = CATS::Problem::Repository->new(
                dir => File::Spec->catdir($CATS::Config::repos_dir, $repo_name) . '/');
            my $bundle = File::Spec->catfile($file, "$repo_name.bundle");
            eval { $repo->bundle($bundle); };
            if (my $err = $@) {
                open my $ferr, '>', File::Spec->catfile($file, "$repo_name.err");
                print $ferr $err;
                print " ... error\n" if !$quiet;
                next;
            }
            my $size = -s $bundle;
            printf " ... ok %d\n", $size if !$quiet;
            $uncompressed_size += $size;
        }
    }
    $result .= sprintf "File: %s\nSize: %s\n", $file, group_digits($uncompressed_size, '_');
    my $backup_ts = [ gettimeofday ];
    my $result_time = sprintf "Backup time: %s\n", CATS::Backup::fmt_interval($start_ts, $backup_ts);

    if ($zip) {
        ($ok, $err, $full) = IPC::Cmd::run command => [ qw(zip -j -1 -q -m -r), $file, $file ];
        $ok or die join "\n", $err, @$full;
        rmdir $file or die "rmdir: $!";
        my $compressed_size = group_digits(-s "$file.zip", '_');
        $result .= "Zipped: $compressed_size\n";
        my $zip_ts = [ gettimeofday ];
        $result_time .= sprintf "Zip time: %s\n", CATS::Backup::fmt_interval($backup_ts, $zip_ts);
        $file .= '.zip';
    }
    CATS::Backup::maybe_chown($chown, $file, $quiet);
    $result .= CATS::Backup::remove_old_backup($dest, $prefix, $max, $quiet) // '' if $max;
    print "\n" if !$quiet;
    $result . $result_time;
}

my $ok = eval { work; };
my $err = $@;
my $text = sprintf "Subject: CATS Repo backup report (%s)\n\n%s\n", $ok ? 'ok' : 'ERROR', $ok // $err;

if ($report eq 'mail') {
    CATS::Mail::send($CATS::Config::health_report_email, $text);
}
else {
    print Encode::encode_utf8($text);
}
