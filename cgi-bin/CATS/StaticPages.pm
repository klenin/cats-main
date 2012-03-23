package CATS::StaticPages;

use strict;
use warnings;

use CGI;
use CATS::DB;

sub allowed_pages
{{
    problem_text => { cid => 1, cpid => 1, pid => 1 },
    rank_table_content => { cid => 1, hide_ooc => 1, printable => 1 },
}}


sub process_static
{
    my $url = $ENV{REDIRECT_URL};
    my ($f, $p) = $url =~ /^\/\w+\/static\/([a-z_]+)-([a-z_\-0-9]+)\.html/;
    $f && $p or die;
    my $ap = allowed_pages()->{$f} or die;
    my %params;
    $p =~ s/([a-z_]+)-(\d+)/$ap->{$1} ? $params{$1} = $2 : ''/eg;
    %params or die;
    my $output_file = path() . name($f, %params) . '.html';
    $params{f} = $f;
    # ����� ������� url_param, ���� �������� QUERY_STRING
    $ENV{QUERY_STRING} = join ';', map "$_=$params{$_}", keys %params;
    CGI::restore_parameters(\%params);
    return $output_file;
}


sub name
{
    my ($f, %p) = @_;
    "$f-" . join('-', map "$_-$p{$_}", sort keys %p);
}


sub url_static { './static/' . name(@_) . '.html'; }
sub path { $ENV{CATS_DIR} . '../static/' }
sub full_name { path() . name(@_) . '.html' }


sub invalidate_problem_text
{
    my (%p) = @_;
    my @contest_ids = $p{cid} ? ($p{cid}) : ();
    my @cpids = $p{cpid} ? ($p{cpid}) : ();
    
    if ($p{pid})
    {
        my $records = $dbh->selectall_arrayref(q~
            SELECT id, contest_id FROM contest_problems WHERE problem_id = ?~,
            undef, $p{pid});
        for my $record (@$records) {
            push @cpids, $$record[0];
            push @contest_ids, $$record[1];
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
