package CATS::UI::ProblemDetails;

use strict;
use warnings;

use CATS::DB;
use CATS::Misc qw(
    $t $is_jury $is_root $sid
    init_template res_str url_f);
use CATS::Utils qw(url_function);

my $problem_submenu = [
    { href => 'problem_details', item => 504 },
    { href => 'problem_history', item => 568 },
    { href => 'compare_tests', item => 552 },
];

sub problem_submenu
{
    my ($selected_href, $pid) = @_;
    $t->param(
        submenu => [ map +{
            href => url_f($_->{href}, pid => $pid),
            item => res_str($_->{item}),
            selected => $_->{href} eq $selected_href }, @$problem_submenu
        ]
    );
}

sub problem_details_frame {
    my ($p) = @_;
    init_template('problem_details.html.tt');
    $is_jury or return;
    $p->{pid} or return;
    my $pr = $dbh->selectrow_hashref(q~
        SELECT P.title, P.lang, P.contest_id, C.title AS contest_name
        FROM problems P
        INNER JOIN contests C ON C.id = P.contest_id
        WHERE P.id = ?~, { Slice => {} },
        $p->{pid});
    $t->param(
        p => $pr,
        title_suffix => $p->{title},
        href_original_contest => url_function('problems', cid => $pr->{contest_id}, sid => $sid),
    );
    problem_submenu('problem_details', $p->{pid});
}

1;
