package CATS::StaticPages;

use strict;
use warnings;

use CGI;


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
    # Чтобы работал url_param, надо заменить QUERY_STRING
    $ENV{QUERY_STRING} = join '&', map "$_=$params{$_}", keys %params;
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


sub refresh_problem_text
{
    my (%p) = @_;
    if ($p{cid})
    {
        my $p = path() . name('problem_text', cid => $p{cid}) . '*';
        `rm $p`;
    }
}


1;
