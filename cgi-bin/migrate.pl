use v5.10;
use strict;
use warnings;

use File::Spec;
use FindBin qw($Bin);
use Getopt::Long;
use POSIX qw();

GetOptions(
    help => \(my $help = 0),
    'make=s' => \(my $make = ''),
    'dry-run' => \(my $dry_run = ''),
    force => \(my $force = 0),
);

sub usage {
    print STDERR qq~CATS migration tool
Usage: $0
  --help
  --make=<name>
  --dry_run
  --force
~;
    exit;
}

usage if $help || !$make;

$make =~ /^[a-z0-9\-_]+$/ or die "Bad migration name: $make";
$make =~ s/_/-/g;

my $diff = `git diff -- sql/interbase`;
$diff or die 'No diff';

my $name = File::Spec->catfile(
    qw(sql interbase migrations),
    POSIX::strftime('%Y%m%d', localtime) . "-$make.sql");
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
        undef $table if m/(:?CREATE|ALTER) TABLE/;
        if ($table) {
            say "ALTER TABLE $table";
            say "    ADD $line;";
        }
        else {
            say $line;
        }
    }
    elsif (my ($line1) = m/^\-([^\-].+)$/) {
        if ($table) {
            say "ALTER TABLE $table";
            say "    DROP $line1;";
        }
        else {
            say; # Unable auto-converl this removal, trigger syntax error.
        }
    }
    elsif (m/@@ CREATE TABLE (\w+) \(/) {
        $table = $1;
    }
}
