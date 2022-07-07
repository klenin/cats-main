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
use CATS::Mail;
use CATS::Problem::Repository;
use CATS::Utils qw(group_digits);

sub usage {
    print STDERR "CATS Repository backup tool
Usage: $0 <options>
Options:
  [--help]\t\tDisplay this help.
  --report={std|mail}\tPrint report to stdout or send it by email.
  [--quiet]\t\tDo not print progress info.
  [--dest=<path>]\tStore backups in a given folder, default is '../backups/repo'.
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

$dest ||= File::Spec->catdir($FindBin::Bin, '..', 'backups', 'repo');

sub fmt_interval {
    my $s = Time::HiRes::tv_interval(@_);
    my $ms = int(1000 * ($s - int($s)));
    my $m = int($s / 60);
    $s %= 60;
    sprintf '%02d:%02d.%03d', $m, $s, $ms;
}

my $prefix = 'catsr-';

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
        my $n = File::Spec->catfile($dest,
            $prefix . strftime('%Y-%m-%d', localtime) . ($i ? "-$i" : ''));
        next if -d $n;
        next if -f "$n.zip" && $zip;
        return $n;
    }
    die "Too many backups at $dest";
}

sub work {
    IPC::Cmd::can_run('git') or die 'Error: git not found';

    my ($ok, $err, $full) = IPC::Cmd::run command => [ 'git', '--version' ];
    $ok && $full && $full->[0] =~ /git version/ or die "Error: git not correct: @$full";

    -d $dest or die "Bad destination: $dest";

    my $file = find_file;

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
            $repo->bundle($bundle);
            my $size = -s $bundle;
            printf " ... ok %d\n", $size if !$quiet;
            $uncompressed_size += $size;
        }
    }
    $result .= sprintf "File: %s\nSize: %s\n", $file, group_digits($uncompressed_size, '_');
    my $backup_ts = [ gettimeofday ];
    my $result_time = sprintf "Backup time: %s\n", fmt_interval($start_ts, $backup_ts);

    if ($zip) {
        ($ok, $err, $full) = IPC::Cmd::run command => [ qw(zip -j -1 -q -m -r), $file, $file ];
        $ok or die join "\n", $err, @$full;
        rmdir $file or die "rmdir: $!";
        my $compressed_size = group_digits(-s "$file.zip", '_');
        $result .= "Zipped: $compressed_size\n";
        my $zip_ts = [ gettimeofday ];
        $result_time .= sprintf "Zip time: %s\n", fmt_interval($backup_ts, $zip_ts);
        $file .= '.zip';
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
my $text = sprintf "Subject: CATS Repo backup report (%s)\n\n%s\n", $ok ? 'ok' : 'ERROR', $ok // $err;

if ($report eq 'mail') {
    CATS::Mail::send($CATS::Config::health_report_email, $text);
}
else {
    print Encode::encode_utf8($text);
}
