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
  --dry-run
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

my $db = $CATS::Config::db;
printf "DBI: %s\nHost: %s\nDatabase: %s\n",
    $db->{driver}, $db->{host}, $db->{name};

my $has_lines;
sub say_c {
    say @_;
    $has_lines = 1;
}
sub say_n {
    say '' if $has_lines;
    say_c @_;
}

sub _make_migration {
    my ($diff, $fout) = @_;

    say "Creating migration: $fout";
    if (!$dry_run) {
       open my $fh, '>', $fout or die $!;
       select $fh;
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

    select STDOUT;
}

sub get_migration_path {
    my $path = File::Spec->catdir($Bin, ('..', 'sql', $_[0], 'migrations'));
    -d $path or die "Migration path not available: $path";
    $path;
}

sub make_migration {
    $make =~ /^[a-z0-9\-_]+$/ or die "Bad migration name: $make";
    $make =~ s/_/-/g;

    my $ib_diff = `git diff -- sql/common sql/interbase`;
    my $pg_diff = `git diff -- sql/common sql/postgres`;
    $ib_diff || $pg_diff or die 'No diff';

    my $name = POSIX::strftime('%Y%m%d', localtime) . "-$make.sql";
    my $ib_path = File::Spec->catfile(get_migration_path('interbase'), $name);
    my $pg_path = File::Spec->catfile(get_migration_path('postgres'), $name);

    if (-f $ib_path) {
        my $err = 'Migration already exists';
        $dry_run ? say $err : $force ? say "$err, forcing" : die $err;
    }

    if ($dry_run) {
        say 'Dry run';
    }
    _make_migration($ib_diff, $ib_path);
    _make_migration($pg_diff, $pg_path);
}

sub apply_migration {
    my $migration_path = get_migration_path($db->{driver} eq 'Firebird' ? 'interbase' : 'postgres');
    opendir my $d, $migration_path or die $!;
    my @files = grep -f, map File::Spec->catfile($migration_path, $_), sort readdir $d;
    my $file = $files[-$apply] or die "No migration for index: $apply";
    say "Applying migration: $file";
    if ($dry_run) {
        say 'Dry run';
        return;
    }

    my $cmd;
    if ($db->{driver} eq 'Firebird') {
        my $isql = $^O eq 'Win32' ? 'isql' : 'isql-fb';
        IPC::Cmd::can_run($isql) or die "Error: $isql not found";
        $cmd = [ $isql, '-b', '-i', $file,
            '-u', $db->{user}, '-p', $db->{password}, '-q', "$db->{host}:$db->{name}" ];
    } elsif ($db->{driver} eq 'Pg') {
        IPC::Cmd::can_run('psql') or die 'Error: psql not found';
        my $dbname = sprintf "postgresql://%s:%s@%s:5432/%s",
            $db->{user}, $db->{password}, $db->{host}, $db->{name};
        $cmd = [ 'psql', '-f', $file, '--dbname', $dbname];
    }
    $cmd or die "Unknown driver: $db->{driver}";

    # say join ' ', 'Running:', @$cmd;
    my ($ok, $err, $full) = IPC::Cmd::run command => $cmd;
    $ok or die join "\n", $err, @$full;
    print '-' x 20, "\n", @$full;
}

$help || $make && $apply ? usage :
    $make ? make_migration :
    $apply ? apply_migration :
    usage;
