package CATS::Problem::Utils;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($t);
use CATS::Messages qw(res_str);
use CATS::Output qw(url_f);

# If the problem was not downloaded yet, generate a hash for it.
sub ensure_problem_hash {
    my ($problem_id, $hash, $need_commit) = @_;
    return 1 if $$hash;
    my @ch = ('a'..'z', 'A'..'Z', '0'..'9');
    $$hash = join '', map @ch[rand @ch], 1..32;
    $dbh->do(q~
        UPDATE problems SET hash = ? WHERE id = ?~, undef,
        $$hash, $problem_id);
    $dbh->commit if $need_commit;
    return 0;
}

sub gen_group_text {
    my ($t) = @_;
    defined $t->{input} && !defined $t->{input_file_size} ? '' :
    $t->{gen_group} ? "$t->{gen_name} GROUP" :
    $t->{gen_name} ? "$t->{gen_name} $t->{param}" : '';
}

sub run_method_enum() {+{
    default => $cats::rm_default,
    interactive => $cats::rm_interactive,
    competitive => $cats::rm_competitive,
}}

my $problem_submenu = [
    { href => 'problem_details', item => 504 },
    { href => 'problem_history', item => 568 },
    { href => 'compare_tests', item => 552 },
    { href => 'problem_select_testsets', item => 505 },
    { href => 'problem_test_data', item => 508 },
    { href => 'problem_limits', item => 507 },
    { href => 'problem_select_tags', item => 506 },
];

sub problem_submenu {
    my ($selected_href, $pid) = @_;
    $t->param(
        submenu => [ map +{
            href => url_f($_->{href}, pid => $pid),
            item => res_str($_->{item}),
            selected => $_->{href} eq $selected_href }, @$problem_submenu
        ]
    );
}

1;
