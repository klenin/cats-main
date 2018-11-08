package CATS::UI::RankTable;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $t $uid);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::RankTable;

our @router_bool_params = qw(
    cache
    hide_ooc
    hide_virtual
    points
    printable
    show_flags
    show_prizes
    show_regions
);

sub rank_table {
    my ($p, $template_name) = @_;
    init_template($p, 'rank_table_content.html.tt');
    $t->param(printable => $p->{printable});
    my $rt = CATS::RankTable->new($p);
    $rt->parse_params($p);
    $rt->rank_table;
    $contest->{title} = $rt->{title};
    my $s = $t->output;

    init_template($p, $template_name);
    $t->param(rank_table_content => $s, printable => $p->{printable});
}

sub rank_table_frame {
    my ($p) = @_;

    #rank_table($p, 'rank_table.htm');
    #init_template($p, 'rank_table_content.htm');
    init_template($p, 'rank_table.html.tt');

    my $rt = CATS::RankTable->new($p);
    $rt->get_contests_info($uid);
    $contest->{title} = $rt->{title};

    my $sites = @{$p->{sites}} ? $dbh->selectall_arrayref(_u $sql->select(
        'sites', 'id, name', { id => $p->{sites} }, 'name')) : [];
    $t->param(problem_title => join '; ', map $_->{name}, @$sites);

    my @params = (
        (map { $_ => $p->{$_} } @router_bool_params),
        clist => $rt->{contest_list},
        filter => Encode::decode_utf8($p->{filter}),
        sites => join(',', map $_->{id}, @$sites) || undef,
        sort => $p->{sort},
    );
    $t->param(href_rank_table_content => url_f('rank_table_content', @params));
    my $submenu =
        [ { href => url_f('rank_table_content', @params, printable => 1), item => res_str(538) } ];
    if ($is_jury) {
        push @$submenu,
            { href => url_f('rank_table', @params, cache => ($p->{cache} ? 0 : 1)), item => res_str(553) },
            { href => url_f('rank_table', @params, points => ($p->{points} ? 0 : 1)), item => res_str(554) };
    }
    $t->param(submenu => $submenu, title_suffix => res_str(529));
}

sub rank_table_content_frame {
    my ($p) = @_;
    rank_table($p, 'rank_table_iframe.html.tt');
}

sub rank_problem_details {
    my ($p) = @_;
    init_template($p, 'rank_problem_details.html.tt');
    $is_jury or return;

    $p->{pid} or return;

    my $runs = $dbh->selectall_arrayref(q~
        SELECT
            R.id, R.state, R.account_id, R.points
        FROM reqs R WHERE R.contest_id = ? AND R.problem_id = ?
        ORDER BY R.id~, { Slice => {} },
        $cid, $p->{pid});

    for (@$runs) {
        1;
    }
}

1;
