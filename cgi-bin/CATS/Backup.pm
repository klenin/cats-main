package CATS::Backup;

use strict;
use warnings;

use File::stat;
use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday);

our $options = <<EOT
  [--help]\t\tDisplay this help.
  --report={std|mail}\tPrint report to stdout or send it by email.
  [--quiet]\t\tDo not print progress info.
  [--dest=<path>]\tStore backups in a given folder, default is '../backups'.
  [--zip]\t\tCompress backup.
  [--chown=<user>]\tChange backup file ownership.
  [--max=<number>]\tRemove oldest backup when maximum count is reached.
  [--imitate]\t\tCreate dummy backup file for testing.
EOT
;

sub fmt_interval {
    my $s = Time::HiRes::tv_interval(@_);
    my $ms = int(1000 * ($s - int($s)));
    my $m = int($s / 60);
    $s %= 60;
    sprintf '%02d:%02d.%03d', $m, $s, $ms;
}

sub find_file {
    my ($dest, $prefix, $zip, $ext, $zip_ext) = @_;
    for (my $i = 0; $i < 10; ++$i) {
        my $n = File::Spec->catfile($dest,
            $prefix . strftime('%Y-%m-%d', localtime) . ($i ? "-$i" : '') . $ext);
        next if -e $n;
        next if $zip && -e "$n.$zip_ext";
        return $n;
    }
    die "Too many backups at $dest";
}

sub remove_old_backup {
    my ($dest, $prefix, $max, $quiet) = @_;
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

sub maybe_chown {
    my ($chown, $file, $quiet) = @_;
    $chown or return;
    print "chown $chown:$chown $file\n" if !$quiet;
    my (undef, undef, $uid, $gid) = getpwnam($chown) or die "User not found: $chown";
    chown $uid, $gid, $file or die "Error: chown: $!";
}

1;
