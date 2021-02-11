package CATS::Contest::Utils;

use strict;
use warnings;

use Encode;
use List::Util qw(reduce);

use CATS::Config;
use CATS::Constants;
use CATS::DB qw(:DEFAULT $db);
use CATS::Globals qw($cid $is_root $sid $t $uid);
use CATS::Messages qw(msg res_str);
#use CATS::Output qw(url_f);
use CATS::StaticPages;
use CATS::Time;
use CATS::Utils qw(url_function date_to_iso);

# Avoid CATS::Output to work on Travis.
sub url_f { CATS::Utils::url_function(@_, sid => $sid, cid => $cid) }
sub url_f_cid { CATS::Utils::url_function(@_, sid => $sid) }

sub common_seq_prefix {
    my ($pa, $pb) = @_;
    my $i = 0;
    ++$i while $i < @$pa && $i < @$pb && $pa->[$i] eq $pb->[$i];
    [ @$pa[0 .. $i - 1] ];
}

sub common_prefix {
    join ' ', @{(reduce { common_seq_prefix($a, $b) } map [ split /\s+|_+|[:,\.]/ ], @_) || []}
}

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
        start_date finish_date freeze_date defreeze_date offset_start_until
        closed is_official rules parent_id
    )
}

sub contest_fields_str {
    join ', ', map("C.$_", contest_fields),
        'CAST(CURRENT_TIMESTAMP - start_date AS DOUBLE PRECISION) AS since_start',
        'CAST(CURRENT_TIMESTAMP - finish_date AS DOUBLE PRECISION) AS since_finish',
        'CAST(CURRENT_TIMESTAMP - offset_start_until AS DOUBLE PRECISION) AS since_offset_start_until',
        'CAST(finish_date - start_date AS DOUBLE PRECISION) AS duration',
        'CAST((finish_date - start_date) * 24 AS DECIMAL(15,1)) AS duration_hours',
}

sub contest_date_fields {
    qw(start_date finish_date freeze_date defreeze_date pub_reqs_date offset_start_until);
}

sub _contest_search_fields() {qw(
    show_all_tests
    show_test_resources
    show_checker_comment
    show_packages
    show_explanations
    show_all_results
    local_only
    show_flags
    max_reqs
    show_test_data
    req_selection
    pinned_judges_only
    show_sites
)}

sub _contest_searches {
    my ($p) = @_;

    $p->{listview}->define_db_searches({
        parent_or_id => 'COALESCE(C.parent_id, C.id)',
        (map { $_ => "C.$_" } contest_fields, _contest_search_fields),
        since_start => 'CAST(CURRENT_TIMESTAMP - start_date AS DOUBLE PRECISION)',
        since_finish => 'CAST(CURRENT_TIMESTAMP - finish_date AS DOUBLE PRECISION)',
        since_offset_start_until => 'CAST(CURRENT_TIMESTAMP - offset_start_until AS DOUBLE PRECISION)',
        duration_hours => 'CAST((finish_date - start_date) * 24 AS DECIMAL(15,1))',
    });
    $p->{listview}->default_searches([ qw(title) ]);
    $p->{listview}->define_enums({
        rules => { icpc => 0, school => 1 },
        parent_id => { this => $cid },
        parent_or_id => { this => $cid },
    });
    my $cp_hidden = $is_root ? '' : " AND CP1.status < $cats::problem_st_hidden";
    $p->{listview}->define_subqueries({
        has_tag => { sq => q~EXISTS (
            SELECT 1 FROM contest_contest_tags CCT1 WHERE CCT1.contest_id = C.id AND CCT1.tag_id = ?)~,
            m => 1191, t => q~
            SELECT CT.name FROM contest_tags CT WHERE CT.id = ?~
        },
        has_tag_named => { sq => q~EXISTS (
            SELECT 1 FROM contest_contest_tags CCT1
            INNER JOIN contest_tags CT1 ON CT1.id = CCT1.tag_id
            WHERE CCT1.contest_id = C.id AND CT1.name = ?)~,
            m => 1191, t => undef,
        },
        has_group => { sq => q~EXISTS (
            SELECT 1 FROM acc_group_contests AGC1 WHERE AGC1.contest_id = C.id AND AGC1.acc_group_id = ?)~,
            m => 1220, t => q~
            SELECT AG.name FROM acc_groups AG WHERE AG.id = ?~
        },
        has_de_tag => { sq => q~EXISTS (
            SELECT 1 FROM contest_de_tags CDT1 WHERE CDT1.contest_id = C.id AND CDT1.tag_id = ?)~,
            m => 1191, t => q~
            SELECT DT.name FROM de_tags DT WHERE DT.id = ?~
        },
        has_de_tag_named => { sq => q~EXISTS (
            SELECT 1 FROM contest_de_tags CDT1
            INNER JOIN de_tags DT1 ON CD1.id = CDT1.tag_id
            WHERE CDT1.contest_id = C.id AND CD1.name = ?)~,
            m => 1191, t => undef,
        },
        has_json => { sq => qq~CASE WHEN EXISTS (
            SELECT 1 FROM contest_problems CP1 INNER JOIN problems P1 ON P1.id = CP1.problem_id
            WHERE CP1.contest_id = C.id AND P1.json_data IS NOT NULL$cp_hidden) THEN 1 ELSE 0 END = ?~,
            #m => 1015, t => q~
            #SELECT P.title FROM problems P WHERE P.id = ?~
        },
        has_wiki => { sq => q~EXISTS (
            SELECT 1 FROM contest_wikis CW
            WHERE CW.contest_id = C.id AND CW.wiki_id = ?)~,
            m => 1211, t => q~
            SELECT W.name FROM wiki_pages W WHERE W.id = ?~
        },
    });
}

sub _common_contests_view {
    my ($c, $p) = @_;
    $c->{$_} = $db->format_date($c->{$_}) for contest_date_fields;
    my $start_date_iso = date_to_iso($c->{start_date});
    return (
        %$c,
        contest_name => $c->{title},
        start_date_iso => $start_date_iso,
        since_start_text => CATS::Time::since_contest_start_text($c->{since_start}),
        finish_date_iso => date_to_iso($c->{finish_date}),
        freeze_date_iso => date_to_iso($c->{freeze_date}),
        unfreeze_date_iso => date_to_iso($c->{defreeze_date}),
        offset_start_until_iso => date_to_iso($c->{offset_start_until}),
        duration_str => CATS::Time::format_diff($c->{duration}),
        registration_denied => $c->{closed},
        selected => $c->{id} == $cid,
        is_official => $c->{is_official},
        show_points => $c->{rules},
        href_params => url_f('contest_params', id => $c->{id}),
        href_results => !$c->{ctype} && url_f_cid('rank_table', cid => $c->{id}),
        href_children => ($c->{child_count} ?
            url_function('contests', sid => $sid, cid => $c->{id}, search => "parent_or_id=$c->{id}") : undef),
        href_problems => url_function('problems', sid => $sid, cid => $c->{id}),
        href_problems_text => CATS::StaticPages::url_static('problem_text', cid => $c->{id}),
        href_start_date => CATS::Time::href_time_zone($start_date_iso, $c->{title}, $c->{duration_hours}),
        href_parent => $c->{parent_id} ? url_function('problems', sid => $sid, cid => $c->{parent_id}) : '',
    );
}

sub authenticated_contests_view {
    my ($p) = @_;
    my $cf = contest_fields_str;
    _contest_searches($p);
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
    $p->{listview}->define_enums({ has_user => { this => $uid } });
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
    my $tags_sql = $p->{listview}->visible_cols->{Tg} ? q~
        SELECT LIST(CT.name, ', ') FROM contest_contest_tags CCT
        INNER JOIN contest_tags CT ON CT.id = CCT.tag_id
        WHERE CCT.contest_id = C.id~ : 'NULL';

    my $c_hidden = $is_root ? '1=1' : q~(CA.account_id IS NOT NULL OR C.is_hidden = 0)~;
    my $sth = $dbh->prepare(qq~
        SELECT
            $cf, CA.is_virtual, CA.is_jury, CA.id AS registered, C.is_hidden,
            (SELECT COUNT(*) FROM contests C1 WHERE C1.parent_id = C.id AND C1.is_hidden = 0) AS child_count,
            ($problems_count_sql) AS problems_count,
            ($tags_sql) AS tags
            $extra_fields
        FROM contests C
        LEFT JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        WHERE
            $c_hidden ~ .
            ($p->{filter_sql} || '') .
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
        $c->{tags_split} = [ split ', ', $c->{tags} // '' ];
        return (
            _common_contests_view($c),
            editable => $c->{is_jury},
            deletable => $is_root,
            registered_online => $c->{registered} && !$c->{is_virtual},
            registered_virtual => $c->{registered} && $c->{is_virtual},
            href_delete => url_f('contests', delete => $c->{id}),
            has_orig => $c->{id} == $original_contest,
            href_contest_tags =>
                $c->{is_jury} ? url_function('contest_tags', cid => $c->{id}, sid => $sid) : '',
        );
    };
    ($fetch_contest, $sth);
}

sub anonymous_contests_view {
    my ($p) = @_;
    my $cf = contest_fields_str;
    _contest_searches($p);
    my $sth = $dbh->prepare(qq~
        SELECT $cf FROM contests C WHERE C.is_hidden = 0 ~ .
       ($p->{filter_sql} || '') .
       $p->{listview}->maybe_where_cond .
       $p->{listview}->order_by
    );
    $sth->execute($p->{listview}->where_params);

    my $fetch_contest = sub {
        my $c = $_[0]->fetchrow_hashref or return;
        _common_contests_view($c, $p);
    };
    ($fetch_contest, $sth);
}

my $contest_submenu = [
    { href => 'contest_params', item => 594 },
    { href => 'contest_problems_installed', item => 595 },
    { href => 'contest_xml', item => 596 },
    { href => 'contest_wikis', item => 589 },
];

sub contest_submenu {
    my ($selected_href, $contest_id) = @_;
    $t->param(
        submenu => [ map +{
            href => CATS::Utils::url_function($_->{href}, sid => $sid, cid => $contest_id),
            item => res_str($_->{item}),
            selected => $_->{href} eq $selected_href,
            new => $_->{new},
        },
            ($selected_href =~ /^contest_wikis/ ?
                ({ href => 'contest_wikis_edit', item => 590, new => 1 }) : ()),
            @$contest_submenu,
            ($is_root ? { href => 'contest_caches', item => 515 } : ()),
        ]
    );
}

sub add_remove_tags {
    my ($p, $table) = @_;
    $p->{add} || $p->{remove} or die;
    my $existing = $dbh->selectcol_arrayref(qq~
        SELECT tag_id FROM $table WHERE contest_id = ?~, undef,
        $cid);
    my %existing_idx;
    @existing_idx{@$existing} = undef;
    my $count = 0;
    if ($p->{add}) {
        my $q = $dbh->prepare(qq~
            INSERT INTO $table (contest_id, tag_id) VALUES (?, ?)~);
        for (@{$p->{check}}) {
            exists $existing_idx{$_} and next;
            $q->execute($cid, $_);
            ++$count;
        }
        $dbh->commit;
        msg(1189, $count);
    }
    elsif ($p->{remove}) {
        my $q = $dbh->prepare(qq~
            DELETE FROM $table WHERE contest_id = ? AND tag_id = ?~);
        for (@{$p->{check}}) {
            exists $existing_idx{$_} or next;
            $q->execute($cid, $_);
            ++$count;
        }
        $dbh->commit;
        msg(1190, $count);
    }
    CATS::StaticPages::invalidate_problem_text(cid => $cid, all => 1) if $count;
}

sub add_remove_groups {
    my ($p) = @_;
    my $existing = $dbh->selectcol_arrayref(q~
        SELECT acc_group_id FROM acc_group_contests WHERE contest_id = ?~, undef,
        $cid);
    my %existing_idx;
    @existing_idx{@$existing} = undef;
    my $count = 0;
    if ($p->{add}) {
        my $q = $dbh->prepare(q~
            INSERT INTO acc_group_contests (contest_id, acc_group_id) VALUES (?, ?)~);
        for (@{$p->{check}}) {
            exists $existing_idx{$_} and next;
            $q->execute($cid, $_);
            ++$count;
        }
        $dbh->commit;
        msg(1218, $count);
    }
    elsif ($p->{remove}) {
        my $q = $dbh->prepare(q~
            DELETE FROM acc_group_contests WHERE contest_id = ? AND acc_group_id = ?~);
        for (@{$p->{check}}) {
            exists $existing_idx{$_} or next;
            $q->execute($cid, $_);
            ++$count;
        }
        $dbh->commit;
        msg(1219, $count);
    }
}

1;
