use v5.10;
use strict;
use warnings;

use File::Spec;
use FindBin qw($Bin);
use Getopt::Long;
use IPC::Cmd;
use POSIX qw();

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');

use CATS::Config;

sub usage {
    print STDERR qq~CATS migration tool
Usage: $0
  --help
  --apply=<index>
  --make=<name>
  --dry_run
  --force
~;
    exit;
}

GetOptions(
    help => \(my $help = 0),
    'apply=i' => \(my $apply = ''),
    'make=s' => \(my $make = ''),
    'dry-run' => \(my $dry_run = ''),
    force => \(my $force = 0),
) or usage;

my $migration_path = File::Spec->catdir($Bin, qw(.. sql interbase migrations));
-d $migration_path or die "Migrations path not available: $migration_path";

my $has_lines;
sub say_c {
    say @_;
    $has_lines = 1;
}
sub say_n {
    say '' if $has_lines;
    say_c @_;
}

sub make_migration() {
    $make =~ /^[a-z0-9\-_]+$/ or die "Bad migration name: $make";
    $make =~ s/_/-/g;

    my $diff = `git diff -- sql/interbase`;
    $diff or die 'No diff';

    my $name = File::Spec->catfile(
        $migration_path, POSIX::strftime('%Y%m%d', localtime) . "-$make.sql");
    say "Creating migration: $name";

    if (-f $name) {
        my $err = 'Migration already exists';
        $dry_run ? say $err : $force ? say "$err, forcing" : die $err;
    }

    if ($dry_run) {
        say 'Dry run';
    }
    else {
       open STDOUT, '>', $name or die $!;
    }

    my $table;
    for (split "\n", $diff) {
        if (my ($line) = m/^\+([^+].+)$/) {
            if (m/(:?CREATE|ALTER) (:?TABLE|INDEX)/) {
                undef $table;
                say_n $line;
            } elsif ($table) {
                $line =~ s/^\s*(.+?),?$/$1/;
                say_n "ALTER TABLE $table";
                say_c "    ADD $line;";
            }
            else {
                say_c $line;
            }
        }
        elsif (my ($line1) = m/^\-([^\-].+)$/) {
            if ($table) {
                say_n "ALTER TABLE $table";
                say_c "    DROP $line1;";
            }
            else {
                say; # Unable auto-convert this removal, trigger syntax error.
            }
        }
        elsif (m/^(?:\s*|.+@@ )CREATE TABLE (\w+) \(/) {
            $table = $1;
        }
    }
}

sub apply_migration() {
    opendir my $d, $migration_path or die $!;
    my @files = grep -f, map File::Spec->catfile($migration_path, $_), sort readdir $d;
    my $file = $files[-$apply] or die "No migration for index: $apply";
    say "Applying migration: $file";
    if ($dry_run) {
        say 'Dry run';
        return;
    }

    my $isql = $^O eq 'Win32' ? 'isql' : 'isql-fb';
    IPC::Cmd::can_run($isql) or die "Error: $isql not found";

    my ($db, $host) = $CATS::Config::db_dsn =~ /dbname=(\S+?);host=(\S+?);/
        or die "Bad config DSN: $CATS::Config::db_dsn";
    say "Host: $host\nDatabase: $db";

    my $cmd = [ $isql, '-b', '-i', $file,
        '-u', $CATS::Config::db_user, '-p', $CATS::Config::db_password, '-q', "$host:$db" ];
    # say join ' ', 'Running:', @$cmd;
    my ($ok, $err, $full) = IPC::Cmd::run command => $cmd;
    $ok or die join "\n", $err, @$full;
    print '-' x 20, "\n", @$full;
}

$help || $make && $apply ? usage :
    $make ? make_migration :
    $apply ? apply_migration :
    usage;
