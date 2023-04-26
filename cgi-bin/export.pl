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
use CATS::Globals qw($cid $is_jury $is_root);
use CATS::ListView;
use CATS::Messages;
use CATS::Template;
use CATS::Verdicts;
use CATS::Web::Mockup;

my $file_pattern_default = '%code%_%id%_%verdict%.%ext%';
#my $header_pattern_default = '%id% %submit_time% %verdict% %orig_fname%.%ext%';

GetOptions(
    'help|h' => \(my $help = 0),
    'contest=i' => \(my $contest_id = 0),
    'mode=s' => \(my $mode = ''),
    'dest=s' => \(my $dest),
    'dry-run' => \(my $dry_run),
    'encoding=s' => \(my $encoding = 'UTF-8'),
    'file-pattern=s' => \(my $file_pattern = $file_pattern_default),
    'header-pattern=s' => \(my $header_pattern = ''),
    'site=i' => \(my $site),
    'search|s=s' => \(my $search = ''),
    'names' => \(my $names),
);

sub usage {
    print STDERR @_, "\n" if @_;
    print STDERR qq~CATS Contest data export tool
Usage: $0 [--help] --contest=<contest id> --mode={log|runs}
    [--dest=<destination dir>]
    [--dry-run]
    [--encoding=<encoding>]
    [--file-pattern=<file name pattern>, default is $file_pattern_default]
    [--header-pattern=<in-file header pattern>, default is none]
    [--names, display field names available for pattern usage]
    [--site=<site id>]
    [--search=<search expression>, search expression, same syntax as a web console]
~;
    exit;
}

usage if $help || !$contest_id;

if ($mode eq 'log') {
}
elsif ($mode eq 'runs') {
    $dest or usage('Error: destination dir required for mode=runs');
    -d $dest or usage("Error: destination dir '$dest' must exist");
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

sub apply_pattern { $_[0] =~ s~%([a-z_]+)%~$_[1]->{$1} // ''~ge }

if ($mode eq 'log') {
    my $t = CATS::Template->new('console_export.xml.tt', cats_dir, { compile_dir => '' });
    $t->param(encoding => $encoding, reqs => CATS::Console::export($contest_id, { site_id => $site }));
    print Encode::encode($encoding, $t->output);
}
elsif ($mode eq 'runs') {
    CATS::Messages::init;
    my $t = CATS::Template->new_dummy;
    my $p = CATS::Web::Mockup->new(search => "$search,contest_id=this", i_value => -1);
    my $lv = CATS::ListView->new(web => $p, name => '', template => $t);
    $cid = $contest_id;
    $is_jury = $is_root = 1;
    CATS::Console::console_searches($lv);
    $CATS::Globals::max_fetch_row_count = 100000;
    my $reqs_sth = CATS::Console::build_query({
        show_results => 1, show_contests => 0, show_messages => 0, i_value => -1, i_unit => 'hours' },
        $lv, []);
    if ($names) {
        print join "\n", sort map lc, @{$reqs_sth->{NAME}};
        exit;
    }
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
            ($r->{orig_fname}, $r->{ext}) = $orig_fname =~ /^(.*?)\.([a-zA-Z0-9]+)?$/;
            $r->{verdict} = $CATS::Verdicts::state_to_name->{$r->{request_state}};
            $r->{points} = $r->{clarified} // 0;
            apply_pattern(my $fn = $file_pattern, $r);
            apply_pattern(my $header = $header_pattern, $r);
            if ($dry_run) {
                print Encode::encode_utf8($fn), (8 < length $fn ? "\t\t" : "\t");
            }
            else {
                my $full_name = File::Spec->catfile($dest, $fn);
                open my $f, '>>', $full_name;
                print $f Encode::encode_utf8("\n$header\n") if $header;
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
