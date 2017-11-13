use v5.10;
use strict;
use warnings;

use Encode;
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
use CATS::Verdicts;

GetOptions(
    help => \(my $help = 0),
    'contest=i' => \(my $contest_id = 0),
    'mode=s' => \(my $mode = ''),
    'dest=s' => \(my $dest),
    'encoding=s' => \(my $encoding = 'UTF-8'),
);

sub usage {
    print STDERR @_, "\n" if @_;
    print STDERR qq~CATS Contest data export tool
Usage: $0 [--help] --contest=<contest id> --mode={log|runs} [--dest=<destination dir>] [--encoding=<encoding>]
~;
    exit;
}

usage if $help || !$contest_id;

if ($mode eq 'log') {
}
elsif ($mode eq 'runs') {
    $dest && -d $dest or usage('Error: destination dir required for mode=runs');
}
else {
    usage(q~Error: mode must be 'log' or 'runs'~);
}

CATS::DB::sql_connect({});

my ($contest_title) = $dbh->selectrow_array(q~
    SELECT title FROM contests WHERE id = ?~, undef, $contest_id) or usage('Error: Unknown contest');
say 'Contest: ', Encode::encode_utf8($contest_title);

if ($mode eq 'log') {
    my $t = CATS::Template->new('console_export.xml.tt', cats_dir, { compile_dir => '' });
    $t->param(encoding => $encoding, reqs => CATS::Console::export($contest_id));
    print $t->output;
}
elsif ($mode eq 'runs') {
    my $reqs = CATS::Console::select_all_reqs($contest_id);
    my $count = 0;
    my $src_sth = $dbh->prepare(q~
        SELECT src, fname FROM sources WHERE req_id= ?~);
    for my $r (@$reqs) {
        $src_sth->execute($r->{id});
        while (my ($src, $fname) = $src_sth->fetchrow_array) {
            my ($ext) = $fname =~ /(\.[a-zA-Z0-9]+)$/;
            my $verdict = $CATS::Verdicts::state_to_name->{$r->{state}};
            open my $f, '>', File::Spec->catfile($dest, "$r->{code}_$r->{id}_$verdict$ext");
            print $f $src;
            ++$count;
        }
        $src_sth->finish;
    }
    say "Runs exported: $count";
}

$dbh->disconnect;
