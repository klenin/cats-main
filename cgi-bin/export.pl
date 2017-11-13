use v5.10;
use strict;
use warnings;

use File::Spec;
use FindBin;
use Getopt::Long;

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::Config;
use CATS::Console;
use CATS::Constants;
use CATS::DB;
use CATS::Template;

GetOptions(
    help => \(my $help = 0),
    'contest=i' => \(my $contest_id = 0),
    'encoding=s' => \(my $encoding = 'UTF-8'),
);

sub usage {
    print STDERR qq~CATS Contest data export tool
Usage: $0 [--help] --contest=<contest id> [--encoding=<encoding>]
~;
    exit;
}

usage if $help || !$contest_id;

CATS::DB::sql_connect({});

my $t = CATS::Template->new('console_export.xml.tt', cats_dir, { compile_dir => '' });
$t->param(encoding => $encoding, reqs => CATS::Console::export($contest_id));
print $t->output;

$dbh->disconnect;
