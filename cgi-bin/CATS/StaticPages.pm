package CATS::StaticPages;

use strict;
use warnings;

use CATS::Config qw(cats_dir);
use CATS::DB;
use CATS::Globals qw($sid);
use CATS::Web qw(log_info url_param restore_parameters);

my $int = qr/^[0-9]+$/;
my $bool = qr/^0|1$/;
my $letters = qr/^[a-z]+$/;

sub allowed_pages {{
    problem_text => { cid => $int, cpid => $int, pid => $int, pl => qr/^[a-z]{2}$/ },
    rank_table_content => { cid => $int, hide_ooc => $bool, printable => $bool },
}}

our $is_static_page;

sub is_static_page { $is_static_page = (url_param('f') || '') eq 'static' }

sub process_static {
    my $url = $ENV{REDIRECT_URL};
    my ($f, $p) = $url =~ /^\/\w+\/static\/([a-z_]+)-([a-z_\-0-9]+)\.html/;
    $f && $p or die $url;
    log_info "generating static page $url";
    my $ap = allowed_pages()->{$f} or die "Unknown static: $f";
    my %params;
    $p =~ s/([a-z_]+)-([^\-]+)/$ap->{$1} ? $params{$1} = $2 : die "Unknown static param: $1"/eg;
    %params or die;
    for (keys %params) {
        $params{$_} =~ $ap->{$_} or die "Bad static param: $_";
    }
    my $output_file = path() . name($f, %params) . '.html';
    $params{f} = $f;
    restore_parameters(\%params);
    return $output_file;
}

sub name {
    my ($f, %p) = @_;
    "$f-" . join('-', map "$_-$p{$_}", sort keys %p);
}

sub url_static { './static/' . name(@_) . '.html' . ($sid ? "?sid=$sid" : ''); }
sub path { cats_dir() . '../static/' }
sub full_name { path() . name(@_) . '.html' }

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
    unlink full_name('problem_text', cid => $_) for @contest_ids;
    unlink full_name('problem_text', cpid => $_) for @cpids;
}

1;
