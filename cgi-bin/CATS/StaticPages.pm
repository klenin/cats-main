package CATS::StaticPages;

use strict;
use warnings;

use CATS::Config qw(cats_dir);
use CATS::DB;
use CATS::Globals qw($sid);
use CATS::RouteParser;

sub allowed_pages {{
    problem_text => { cid => integer, cpid => integer, pid => integer, pl => qr/^[a-z]{2}$/ },
    rank_table_content => { cid => integer, hide_ooc => bool0, printable => bool0 },
}}

our $is_static_page;

sub is_static_page { $is_static_page = $_[0]->{f} eq 'static' }

sub process_static {
    my ($p) = @_;
    my $url = $ENV{REDIRECT_URL};
    my ($f, $param_str) = $url =~ /^\/\w+\/static\/([a-z_]+)-([a-z_\-0-9]+)\.html/;
    $f && $param_str or die $url;
    $p->log_info("generating static page $url");
    my $ap = allowed_pages()->{$f} or die "Unknown static: $f";
    my %params;
    $param_str =~ s/([a-z_]+)-([^\-]+)/
        $ap->{$1} ? $params{$1} = $2 : die "Unknown static param: $1"/eg;
    %params or die;
    for (keys %params) {
        $params{$_} =~ $ap->{$_} or die "Bad static param: $_";
    }
    my $output_file = path() . _name($f, %params) . '.html';
    $p->{f} = $f;
    $p->{$_} = $params{$_} for keys %params;
    $output_file;
}

sub _name {
    my ($f, %p) = @_;
    "$f-" . join('-', map "$_-$p{$_}", grep $p{$_}, sort keys %p);
}

sub url_static { './static/' . _name(@_) . '.html' . ($sid ? "?sid=$sid" : ''); }
sub path { cats_dir() . '../static/' }
sub full_name { path() . _name(@_) . '.html' }
sub full_name_glob { path() . _name(@_) . '*.html' }

sub invalidate_problem_text {
    my (%p) = @_;
    my @contest_ids = $p{cid} ? ($p{cid}) : ();
    my @cpids = $p{cpid} ? ($p{cpid}) : ();

    if ($p{pid}) {
        my $records = $dbh->selectall_arrayref(q~
            SELECT id, contest_id FROM contest_problems WHERE problem_id = ?~,
            undef, $p{pid});
        for my $record (@$records) {
            push @cpids, $record->[0];
            push @contest_ids, $record->[1];
        }
    }
    if ($p{all} && $p{cid}) {
        my $c = $dbh->selectcol_arrayref(q~
            SELECT id FROM contest_problems WHERE contest_id = ?~,
            undef, $p{cid});
        push @cpids, @$c;
    }
    unlink glob full_name_glob('problem_text', cid => $_) for @contest_ids;
    unlink glob full_name_glob('problem_text', cpid => $_) for @cpids;
}

1;
