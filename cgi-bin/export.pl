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

my $file_pattern_default = '%code%_%id%_%verdict%';

GetOptions(
    help => \(my $help = 0),
    'contest=i' => \(my $contest_id = 0),
    'mode=s' => \(my $mode = ''),
    'dest=s' => \(my $dest),
    'dry-run' => \(my $dry_run),
    'encoding=s' => \(my $encoding = 'UTF-8'),
    'file-pattern=s' => \(my $file_pattern = $file_pattern_default),
);

sub usage {
    print STDERR @_, "\n" if @_;
    print STDERR qq~CATS Contest data export tool
Usage: $0 [--help] --contest=<contest id> --mode={log|runs}
    [--dest=<destination dir>]
    [--dry-run]
    [--encoding=<encoding>]
    [--file-pattern=<file name pattern>, default is $file_pattern_default]
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
say STDERR 'Contest: ', Encode::encode_utf8($contest_title);

if ($mode eq 'log') {
    my $t = CATS::Template->new('console_export.xml.tt', cats_dir, { compile_dir => '' });
    $t->param(encoding => $encoding, reqs => CATS::Console::export($contest_id));
    print Encode::encode($encoding, $t->output);
}
elsif ($mode eq 'runs') {
    my $reqs = CATS::Console::select_all_reqs($contest_id);
    my $count = 0;
    my $src_sth = $dbh->prepare(q~
        SELECT src, fname FROM sources WHERE req_id = ?~);
    for my $r (@$reqs) {
        $src_sth->execute($r->{id});
        while (my ($src, $orig_fname) = $src_sth->fetchrow_array) {
            ($r->{orig_fname}, my $ext) = $orig_fname =~ /^(.*)(\.[a-zA-Z0-9]+)$/;
            $r->{verdict} = $CATS::Verdicts::state_to_name->{$r->{state}};
            (my $fn = $file_pattern) =~ s~%([a-z_]+)%~$r->{$1} // ''~ge;
            if ($dry_run) {
                print $fn, (8 < length $fn ? "\t\t" : "\t");
            }
            else {
                open my $f, '>', File::Spec->catfile($dest, "$fn$ext");
                print $f $src;
            }
            ++$count;
        }
        $src_sth->finish;
    }
    say '' if $dry_run;
    say "Runs exported: $count";
}

$dbh->disconnect;
