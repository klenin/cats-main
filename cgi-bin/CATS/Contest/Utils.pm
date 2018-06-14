package CATS::Contest::Utils;

use strict;
use warnings;

use List::Util qw(reduce);

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($cid $is_root $sid $t $uid);
use CATS::Messages qw(res_str);
#use CATS::Output qw(url_f);
use CATS::Utils qw(url_function date_to_iso);

# Avoid CATS::Output to work on Travis.
sub url_f { CATS::Utils::url_function(@_, sid => $sid, cid => $cid) }

sub common_seq_prefix {
    my ($pa, $pb) = @_;
    my $i = 0;
    ++$i while $i < @$pa && $i < @$pb && $pa->[$i] eq $pb->[$i];
    [ @$pa[0 .. $i - 1] ];
}

sub common_prefix { join ' ', @{(reduce { common_seq_prefix($a, $b) } map [ split /\s+|_+/ ], @_) || []} }

sub contest_group_by_clist {
    $dbh->selectrow_array(q~
        SELECT id FROM contest_groups WHERE clist = ?~, undef,
        $_[0]);
}

sub contest_fields () {
    # HACK: starting page is a contests list, displayed very frequently.
    # In the absense of a filter, select only the first page + 1 record.
    # my $s = $settings->{$listview_name};
    # (($s->{page} || 0) == 0 && !$s->{search} ? 'FIRST ' . ($s->{rows} + 1) : '') .
    qw(
        ctype id title short_descr
        start_date finish_date freeze_date defreeze_date closed is_official rules
    )
}

sub contest_fields_str {
    join ', ', map("C.$_", contest_fields),
        'CURRENT_TIMESTAMP - start_date AS since_start',
        'CURRENT_TIMESTAMP - finish_date AS since_finish',
}

sub _contest_search_fields() {qw(
    show_all_tests
    show_test_resources
    show_checker_comment
    show_packages
    show_all_results
    local_only
    show_flags
    max_reqs
    show_test_data
    req_selection
    pinned_judges_only
    show_sites
)}

sub contest_searches { return {
    (map { $_ => "C.$_" } contest_fields, _contest_search_fields),
    since_start => '(CURRENT_TIMESTAMP - start_date)',
    since_finish => '(CURRENT_TIMESTAMP - finish_date)',
}}

sub common_contests_view {
    my ($c) = @_;
    return (
        %$c,
        contest_name => $c->{title},
        short_descr => $c->{short_descr},
        start_date => $c->{start_date},
        since_start => $c->{since_start},
        start_date_iso => date_to_iso($c->{start_date}),
        finish_date => $c->{finish_date},
        since_finish => $c->{since_finish},
        finish_date_iso => date_to_iso($c->{finish_date}),
        freeze_date_iso => date_to_iso($c->{freeze_date}),
        unfreeze_date_iso => date_to_iso($c->{defreeze_date}),
        registration_denied => $c->{closed},
        selected => $c->{id} == $cid,
        is_official => $c->{is_official},
        show_points => $c->{rules},
        href_contest => url_function('contests', sid => $sid, set_contest => 1, cid => $c->{id}),
        href_params => url_f('contest_params', id => $c->{id}),
        href_problems => url_function('problems', sid => $sid, cid => $c->{id}),
        href_problems_text => CATS::StaticPages::url_static('problem_text', cid => $c->{id}),
    );
}

sub authenticated_contests_view {
    my ($p) = @_;
    my $cf = contest_fields_str;
    $p->{listview}->define_db_searches(contest_searches);
    $p->{listview}->define_db_searches({
        is_virtual => 'CA.is_virtual',
        is_jury => 'CA.is_jury',
        is_hidden => 'C.is_hidden',
        'CA.is_hidden' => 'CA.is_hidden',
    });
    my $cp_hidden = $is_root ? '' : " AND CP1.status < $cats::problem_st_hidden";
    my $ca_hidden = $is_root ? '' : " AND CA1.is_hidden = 0";
    $p->{listview}->define_subqueries({
        has_problem => { sq => qq~EXISTS (
            SELECT 1 FROM contest_problems CP1 WHERE CP1.contest_id = C.id AND CP1.problem_id = ?$cp_hidden)~,
            m => 1015, t => q~
            SELECT P.title FROM problems P WHERE P.id = ?~
        },
        has_site => { sq => q~EXISTS (
            SELECT 1 FROM contest_sites CS WHERE CS.contest_id = C.id AND CS.site_id = ?)~,
            m => 1030, t => q~
            SELECT S.name FROM sites S WHERE S.id = ?~
        },
        has_user => { sq => qq~EXISTS (
            SELECT 1 FROM contest_accounts CA1 WHERE CA1.contest_id = C.id AND CA1.account_id = ?$ca_hidden)~,
            m => 1031, t => q~
            SELECT A.team_name FROM accounts A WHERE A.id = ?~
        },
    });
    my $extra_fields = $p->{extra_fields} ? join ',', '', @{$p->{extra_fields}} : '';
    my $problems_count_sql = ($is_root && $p->{listview}->visible_cols->{Pc}) ? q~
        SELECT COUNT(*) FROM contest_problems CP WHERE CP.contest_id = C.id~ : 'NULL';
    if ($is_root) {
        $p->{listview}->define_db_searches({
            problems_count => "($problems_count_sql)",
            original_count => q~
                (SELECT COUNT(*) FROM problems P WHERE P.contest_id = C.id)~,
        });
    }

    my $sth = $dbh->prepare(qq~
        SELECT
            $cf, CA.is_virtual, CA.is_jury, CA.id AS registered, C.is_hidden,
            ($problems_count_sql) AS problems_count
            $extra_fields
        FROM contests C
        LEFT JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        WHERE
            (CA.account_id IS NOT NULL OR COALESCE(C.is_hidden, 0) = 0) ~ .
            ($p->{filter} || '') .
            $p->{listview}->maybe_where_cond .
            $p->{listview}->order_by);
    $sth->execute($uid, $p->{listview}->where_params);

    my $original_contest = 0;
    if (my $pid = $p->{listview}->qb->search_subquery_value('has_problem')) {
        $original_contest = $dbh->selectrow_array(q~
            SELECT P.contest_id FROM problems P WHERE P.id = ?~, undef,
            $pid) // 0;
    }
    my $fetch_contest = sub {
        my $c = $_[0]->fetchrow_hashref or return;
        return (
            common_contests_view($c),
            is_hidden => $c->{is_hidden},
            authorized => 1,
            editable => $c->{is_jury},
            deletable => $is_root,
            registered_online => $c->{registered} && !$c->{is_virtual},
            registered_virtual => $c->{registered} && $c->{is_virtual},
            href_delete => url_f('contests', delete => $c->{id}),
            has_orig => $c->{id} == $original_contest,
        );
    };
    ($fetch_contest, $sth);
}

sub anonymous_contests_view {
    my ($p) = @_;
    my $cf = contest_fields_str;
    $p->{listview}->define_db_searches(contest_searches);
    my $sth = $dbh->prepare(qq~
        SELECT $cf FROM contests C WHERE COALESCE(C.is_hidden, 0) = 0 ~ .
       ($p->{filter} || '') . $p->{listview}->order_by
    );
    $sth->execute;

    my $fetch_contest = sub {
        my $c = $_[0]->fetchrow_hashref or return;
        common_contests_view($c);
    };
    ($fetch_contest, $sth);
}

my $contest_submenu = [
    { href => 'contest_params', item => 594 },
    { href => 'contest_problems_installed', item => 595 },
    { href => 'contest_xml', item => 596 },
];

sub contest_submenu {
    my ($selected_href, $contest_id) = @_;
    $t->param(
        submenu => [ map +{
            href => CATS::Utils::url_function($_->{href}, sid => $sid, cid => $contest_id),
            item => res_str($_->{item}),
            selected => $_->{href} eq $selected_href }, @$contest_submenu
        ]
    );
}

1;
