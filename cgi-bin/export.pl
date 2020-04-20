use v5.10;
use strict;
use warnings;

use Encode;
use File::Spec;
use FindBin;
use Getopt::Long;
use SQL::Abstract;

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::Config;
use CATS::Console;
use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($is_jury $is_root);
use CATS::ListView;
use CATS::Messages;
use CATS::Template;
use CATS::Verdicts;
use CATS::Web::Mockup;

my $file_pattern_default = '%code%_%id%_%verdict%';

GetOptions(
    help => \(my $help = 0),
    'contest=i' => \(my $contest_id = 0),
    'mode=s' => \(my $mode = ''),
    'dest=s' => \(my $dest),
    'dry-run' => \(my $dry_run),
    'encoding=s' => \(my $encoding = 'UTF-8'),
    'file-pattern=s' => \(my $file_pattern = $file_pattern_default),
    'site=i' => \(my $site),
    'search=s' => \(my $search = ''),
);

sub usage {
    print STDERR @_, "\n" if @_;
    print STDERR qq~CATS Contest data export tool
Usage: $0 [--help] --contest=<contest id> --mode={log|runs}
    [--dest=<destination dir>]
    [--dry-run]
    [--encoding=<encoding>]
    [--file-pattern=<file name pattern>, default is $file_pattern_default]
    [--site=<site id>]
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

CATS::DB::sql_connect({
    ib_timestampformat => '%d.%m.%Y %H:%M',
    ib_dateformat => '%d.%m.%Y',
    ib_timeformat => '%H:%M:%S',
});

my ($contest_title) = $dbh->selectrow_array(q~
    SELECT title FROM contests WHERE id = ?~, undef, $contest_id) or usage('Error: Unknown contest');
say STDERR 'Contest: ', Encode::encode_utf8($contest_title);

if ($site) {
    my ($site_name) = $dbh->selectrow_array(q~
        SELECT name FROM sites WHERE id = ?~, undef,
        $site) or usage('Error: unknown site');
    say STDERR 'Site: ', Encode::encode_utf8($site_name);
}

if ($mode eq 'log') {
    my $t = CATS::Template->new('console_export.xml.tt', cats_dir, { compile_dir => '' });
    $t->param(encoding => $encoding, reqs => CATS::Console::export($contest_id, { site_id => $site }));
    print Encode::encode($encoding, $t->output);
}
elsif ($mode eq 'runs') {
    CATS::Messages::init;
    my $t = CATS::Template->new_dummy;
    my $p = CATS::Web::Mockup->new(search => $search . ",contest_id=$contest_id", i_value => -1);
    my $lv = CATS::ListView->new(web => $p, name => '', template => $t);
    $is_jury = $is_root = 1;
    CATS::Console::console_searches($lv);
    $CATS::Globals::max_fetch_row_count = 100000;
    my $reqs_sth = CATS::Console::build_query({
        show_results => 1, show_contests => 0, show_messages => 0, i_value => -1, i_unit => 'hours' },
        $lv, []);
    my $count = 0;
    my $src_sth = $dbh->prepare(q~
        SELECT src, fname FROM sources WHERE req_id = ?~);
    while (my $r = $reqs_sth->fetchrow_hashref) {
        #say "$_ : ", $r->{$_} // 'undef' for sort keys %$r; last;
        $src_sth->execute($r->{id});
        while (1) {
            my ($src, $orig_fname) = eval { $src_sth->fetchrow_array };
            if (my $err = $@) {
                say "Error: $err";
                next;
            }
            $orig_fname or last;
            ($r->{orig_fname}, my $ext) = $orig_fname =~ /^(.*?)(\.[a-zA-Z0-9]+)?$/;
            $r->{verdict} = $CATS::Verdicts::state_to_name->{$r->{request_state}};
            (my $fn = $file_pattern) =~ s~%([a-z_]+)%~$r->{$1} // ''~ge;
            if ($dry_run) {
                print Encode::encode_utf8($fn), (8 < length $fn ? "\t\t" : "\t");
            }
            else {
                open my $f, '>', File::Spec->catfile($dest, $fn . ($ext // ''));
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
