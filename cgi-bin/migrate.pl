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

my @verbose_options = qw(apply_run db_config none show_numbers);
my $verbose_default = 'db_config,show_numbers';

sub usage {
    print STDERR qq~CATS migration tool
Usage: $0
  --help
  --apply=<index>
  --make=<name>
  --dry-run
  --force
  --show=<num>
  --verbose=<options>, default is $verbose_default
      available options: @{[ join ' ', @verbose_options ]}
~;
    exit;
}

GetOptions(
    help => \(my $help = 0),
    'apply=i' => \(my $apply = ''),
    'make=s' => \(my $make = ''),
    'dry-run' => \(my $dry_run = ''),
    force => \(my $force = 0),
    'show=i' => \(my $show = 0),
    'verbose=s'=> \(my $verbose_str = $verbose_default),
) or usage;

my %verbose = map { $_ => 1 } split /,/, $verbose_str;
{
    my %unknown = %verbose;
    delete @unknown{@verbose_options};
    if (%unknown) {
        say 'Unknown verbose options: ', join ',', sort keys %unknown;
        usage;
    }
}

my $db = $CATS::Config::db;
printf "DBI: %s\nHost: %s\nDatabase: %s\n\n",
    $db->{driver}, $db->{host}, $db->{name} if $verbose{db_config};

my $has_lines;
sub say_c {
    say @_;
    $has_lines = 1;
}
sub say_n {
    say '' if $has_lines;
    say_c @_;
}

sub parse_diff {
    my $diff = shift;
    my $table;
    for (split "\n", $diff) {
        if (my ($line) = m/^\+([^+].+)$/) {
            if (m/(:?CREATE|ALTER)\s+(:?TABLE|INDEX)/ || m/(:?GRANT|REVOKE)\s/) {
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
        elsif (my ($line1) = m/^\-([^\-].+?),?$/) {
            if ($table) {
                say_n "ALTER TABLE $table";
                say_c "    DROP $line1;";
            }
            else {
                say; # Unable to auto-convert this removal, trigger syntax error.
            }
        }
        elsif (m/^(?:\s*|.+@@ )CREATE TABLE (\w+) \(/) {
            $table = $1;
        }
    }
}

sub get_migrations_path {
    File::Spec->catdir($Bin, qw(.. sql migrations));
}

sub write_migration {
    my ($migration_path, $header, $diff) = @_;
    $migration_path = File::Spec->catfile(get_migrations_path, $migration_path);
    if (-f $migration_path) {
        my $err = 'Migration already exists';
        $dry_run ? say $err : $force ? say "$err, forcing" : die $err;
    }

    say "Creating migration: $migration_path";
    if (!$dry_run) {
       open my $fh, '>', $migration_path or die $!;
       select $fh;
    }
    say $header if $header;
    parse_diff($diff);
    select STDOUT;
}

sub make_migration {
    $make =~ /^[a-z0-9\-_]+$/ or die "Bad migration name: $make";
    $make =~ s/_/-/g;

    my $common_diff = `git diff -- sql/common`;
    my $ib_diff = `git diff -- sql/interbase`;
    my $pg_diff = `git diff -- sql/postgres`;
    $common_diff || $ib_diff || $pg_diff or die 'No diff';

    say 'Dry run' if $dry_run;

    my $name = POSIX::strftime('%Y%m%d', localtime) . "-$make";
    my $common_name;
    if ($common_diff) {
        $common_name = $name . '.sql';
        write_migration($common_name, '', $common_diff);
    }
    if ($ib_diff) {
        my $header = $common_name ? "INPUT $common_name;" : '';
        write_migration("$name.firebird.sql", $header, $ib_diff);
    }
    if ($pg_diff) {
        my $header = $common_name ? "\\i $common_name" : '';
        write_migration("$name.postgres.sql", $header, $pg_diff);
    }
}

sub get_migration_dbms {
    $db->{driver} eq 'Firebird' ? 'firebird' : 'postgres';
}

sub filename {
    my ($volume, $directories, $file) = File::Spec->splitpath($_[0]);
    $file;
}

sub get_migrations {
    my $migration_path = get_migrations_path;
    -d $migration_path or die "Migrations path not available: $migration_path";
    opendir my $d, $migration_path or die $!;
    my @files = grep -f, map File::Spec->catfile($migration_path, $_), readdir $d;

    my %migrations = ();
    foreach (@files) {
        my $file = filename($_);
        $file =~ m/^([a-z0-9\-_]+)(\.([a-z]+))?\.sql$/;
        if (!exists $migrations{$1}) {
            $migrations{$1} = {};
        }
        my $migration = $migrations{$1};
        $migration->{name} = $1;
        $migration->{$2 ? substr $2, 1 : 'common'} = $_;
    }
    my $dbms = get_migration_dbms;
    grep { exists $_->{common} || exists $_->{$dbms} }
        sort { $a->{name} cmp $b->{name} } values %migrations;
}

sub apply_migration {
    my @migrations = get_migrations;
    my $migration = $migrations[-$apply] or die "No migration for index: $apply";
    my $dbms = get_migration_dbms;
    my $file = $migration->{$dbms} // $migration->{common};
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
        $cmd = [ 'psql', '-f', $file, '--dbname', $dbname ];
    }
    $cmd or die "Unknown driver: $db->{driver}";

    chdir File::Spec->catdir($Bin, qw(.. sql migrations)) or die "Unable to chdir sql/migrations: $!";
    say join ' ', 'Running:', @$cmd if $verbose{apply_run};
    my ($ok, $err, $full) = IPC::Cmd::run command => $cmd;
    $ok or die join "\n", $err, @$full;
    print '-' x 20, "\n", @$full;
}

sub show_migrations {
    my @migrations = get_migrations;
    splice(@migrations, 0, -$show);

    my $i = @migrations;
    my $max_len = length($i);
    my $sep = "\n" . ($verbose{show_numbers} ? ' ' x ($max_len + 2) : '');
    my $fmt = $verbose{show_numbers} ? "%*d. %s\n" : "%3\$s\n";
    for my $m (@migrations) {
        printf $fmt, $max_len, $i--,
            join $sep, map filename($_), grep $_, @$m{qw(common firebird postgres)};
    }
}

$help || $make && $apply ? usage :
    $make ? make_migration :
    $apply ? apply_migration :
    $show ? show_migrations :
    usage;
