package CATS::UI::Contests;

use strict;
use warnings;

use CATS::Constants;
use CATS::ContestParticipate qw(get_registered_contestant);
use CATS::DB;
use CATS::ListView;
use CATS::Misc qw(
    $t $is_jury $is_root $is_team $privs $sid $cid $uid $contest $is_virtual $settings
    init_template msg res_str url_f auto_ext);
use CATS::RankTable;
use CATS::StaticPages;
use CATS::UI::Prizes;
use CATS::Utils qw(url_function coalesce date_to_iso);
use CATS::Web qw(param param_on url_param redirect);

sub contests_new_frame {
    init_template('contests_new.html.tt');

    my $date = $dbh->selectrow_array(q~SELECT CURRENT_TIMESTAMP FROM RDB$DATABASE~);
    $date =~ s/\s*$//;
    $t->param(
        start_date => $date, freeze_date => $date,
        finish_date => $date, open_date => $date,
        can_edit => 1,
        is_hidden => !$is_root,
        show_all_results => 1,
        href_action => url_f('contests')
    );
}

sub contest_checkbox_params() {qw(
    free_registration run_all_tests
    show_all_tests show_test_resources show_checker_comment show_all_results
    is_official show_packages local_only is_hidden show_test_data pinned_judges_only
)}

sub contest_string_params() {qw(
    contest_name short_descr start_date freeze_date finish_date open_date rules req_selection max_reqs
)}

sub get_contest_html_params {
    my $p = {};

    $p->{$_} = scalar param($_) for contest_string_params();
    $p->{$_} = param_on($_) for contest_checkbox_params();

    for ($p->{contest_name}) {
        $_ //= '';
        s/^\s+|\s+$//g;
        $_ ne '' && length $_ < 100  or return msg(1027);
    }
    $p;
}

sub contests_new_save {
    my $p = get_contest_html_params() or return;

    my $new_cid = new_id;
    # free_registration => closed
    $p->{free_registration} = !$p->{free_registration};
    eval { $dbh->do(q~
        INSERT INTO contests (
            id, title, short_descr, start_date, freeze_date, finish_date, defreeze_date, rules, req_selection, max_reqs,
            ctype,
            closed, run_all_tests, show_all_tests,
            show_test_resources, show_checker_comment, show_all_results,
            is_official, show_packages, local_only, is_hidden, show_frozen_reqs, show_test_data, pinned_judges_only
        ) VALUES(
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            0,
            ?, ?, ?,
            ?, ?, ?,
            ?, ?, ?, ?, 0, ?, ?)~,
        {},
        $new_cid, @$p{contest_string_params()},
        @$p{contest_checkbox_params()}
    ); 1; } or return msg(1026, $@);

    # Automatically register all admins as jury.
    my $root_accounts = $dbh->selectcol_arrayref(q~
        SELECT id FROM accounts WHERE srole = ?~, undef,
        $cats::srole_root);
    push @$root_accounts, $uid unless $is_root; # User with contests_creator role.
    for (@$root_accounts) {
        $contest->register_account(
            contest_id => $new_cid, account_id => $_,
            is_jury => 1, is_pop => 1, is_hidden => 1);
    }
    $dbh->commit;
    msg(1028, Encode::decode_utf8($p->{contest_name}));
}

sub try_contest_params_frame {
    my $id = url_param('params') or return;

    init_template('contest_params.html.tt');

    my $p = $dbh->selectrow_hashref(qq~
        SELECT
            title AS contest_name,
            short_descr,
            start_date,
            freeze_date,
            finish_date,
            defreeze_date AS open_date,
            1 - closed AS free_registration,
            run_all_tests, show_all_tests, show_test_resources, show_checker_comment, show_test_data,
            show_all_results, is_official, show_packages, local_only, rules, req_selection,
            is_hidden, max_reqs, pinned_judges_only
        FROM contests WHERE id = ?~, { Slice => {} },
        $id
    ) or return;
    $t->param(
        id => $id, %$p,
        href_action => url_f('contests'),
        privs => $privs,
        can_edit => (get_registered_contestant(fields => 'is_jury', contest_id => $id) ? 1 : 0),
    );

    1;
}

sub contests_edit_save {
    my $edit_cid = param('id');

    my $p = get_contest_html_params() or return;

    # free_registration => closed
    $p->{free_registration} = !$p->{free_registration};
    eval {
        $dbh->do(qq~
            UPDATE contests SET
                title=?, short_descr=?, start_date=?, freeze_date=?,
                finish_date=?, defreeze_date=?, rules=?, req_selection=?, max_reqs=?,
                closed=?, run_all_tests=?, show_all_tests=?,
                show_test_resources=?, show_checker_comment=?, show_all_results=?,
                is_official=?, show_packages=?,
                local_only=?, is_hidden=?, show_frozen_reqs=0, show_test_data=?, pinned_judges_only=?
            WHERE id=?~,
            {},
            @$p{contest_string_params()},
            @$p{contest_checkbox_params()},
            $edit_cid
        );
        $dbh->commit;
        1;
    } or return msg(1035, $@);
    CATS::StaticPages::invalidate_problem_text(cid => $edit_cid, all => 1);
    CATS::RankTable::remove_cache($edit_cid);
    my $contest_name = Encode::decode_utf8($p->{contest_name});
    # Change page title immediately if the current contest is renamed.
    $contest->{title} = $contest_name if $edit_cid == $cid;
    msg(1036, $contest_name);
}

sub contests_select_current {
    defined $uid or return;

    my ($registered, $is_virtual, $is_jury) = get_registered_contestant(
        fields => '1, is_virtual, is_jury', contest_id => $cid
    );
    return if $is_jury;

    $t->param(selected_contest_title => $contest->{title});

    if ($contest->{time_since_finish} > 0) {
        msg(1115, $contest->{title});
    }
    elsif (!$registered) {
        msg(1116);
    }
}

sub common_contests_view {
    my ($c) = @_;
    return (
        id => $c->{id},
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
        href_params => url_f('contests', params => $c->{id}),
        href_problems => url_function('problems', sid => $sid, cid => $c->{id}),
        href_problems_text => CATS::StaticPages::url_static('problem_text', cid => $c->{id}),
    );
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

sub contest_searches { return {
    (map { $_ => "C.$_" } contest_fields),
    since_start => '(CURRENT_TIMESTAMP - start_date)',
    since_finish => '(CURRENT_TIMESTAMP - finish_date)',
}}

sub contests_submenu_filter {
    my $f = $settings->{contests}->{filter} || '';
    {
        all => '',
        official => 'AND C.is_official = 1 ',
        unfinished => 'AND CURRENT_TIMESTAMP <= finish_date ',
        current => 'AND CURRENT_TIMESTAMP BETWEEN start_date AND finish_date ',
        json => q~
            AND EXISTS (
                SELECT 1 FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
                WHERE CP.contest_id = C.id AND P.json_data IS NOT NULL)~,
    }->{$f} || '';
}

sub authenticated_contests_view {
    my ($p) = @_;
    my $cf = contest_fields_str;
    my $original_contest = 0;
    if ($p->{has_problem}) {
        my ($has_problem_pid) = $dbh->selectrow_array(q~
            SELECT CP.problem_id FROM contest_problems CP WHERE CP.id = ?~, undef,
            $p->{has_problem});
        $p->{has_problem} = $has_problem_pid if $has_problem_pid;
        ($original_contest, my $title) = $dbh->selectrow_array(q~
            SELECT P.contest_id, P.title FROM problems P WHERE P.id = ?~, undef, $p->{has_problem});
        if ($original_contest) {
            msg(1015, $title);
        }
        else {
            $p->{has_problem} = undef;
        }
    }
    $p->{listview}->define_db_searches(contest_searches);
    $p->{listview}->define_db_searches({
        is_virtual => 'CA.is_virtual',
        is_jury => 'CA.is_jury',
        is_hidden => 'C.is_hidden',
        'CA.is_hidden' => 'CA.is_hidden',
    });
    my $sth = $dbh->prepare(qq~
        SELECT
            $cf, CA.is_virtual, CA.is_jury, CA.id AS registered, C.is_hidden
        FROM contests C LEFT JOIN
            contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        WHERE
            (CA.account_id IS NOT NULL OR COALESCE(C.is_hidden, 0) = 0) ~ .
            ($p->{has_problem} ? q~AND EXISTS (
                SELECT 1 FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.problem_id = ?) ~ : contests_submenu_filter()) .
            $p->{listview}->maybe_where_cond .
            $p->{listview}->order_by);
    $sth->execute($uid, $p->{has_problem} ? $p->{has_problem} : (), $p->{listview}->where_params);

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
    return ($fetch_contest, $sth);
}

sub anonymous_contests_view {
    my ($p) = @_;
    my $cf = contest_fields_str;
    $p->{listview}->define_db_searches(contest_searches);
    my $sth = $dbh->prepare(qq~
        SELECT $cf FROM contests C WHERE COALESCE(C.is_hidden, 0) = 0 ~ .
        contests_submenu_filter() . $p->{listview}->order_by
    );
    $sth->execute;

    my $fetch_contest = sub {
        my $c = $_[0]->fetchrow_hashref or return;
        return common_contests_view($c);
    };
    return ($fetch_contest, $sth);
}

sub contest_delete {
    my $delete_cid = url_param('delete');
    $is_root or return;
    my ($cname, $problem_count) = $dbh->selectrow_array(q~
        SELECT title, (SELECT COUNT(*) FROM contest_problems CP WHERE CP.contest_id = C.id) AS pc
        FROM contests C WHERE C.id = ?~, undef,
        $delete_cid);
    $cname or return;
    return  msg(1038, $cname, $problem_count) if $problem_count;
    $dbh->do(q~
        DELETE FROM contests WHERE id = ?~, undef,
        $delete_cid);
    $dbh->commit;
    msg(1037, $cname);
}

sub contests_frame {
    my ($p) = @_;

    if (defined param('summary_rank')) {
        my @clist = param('contests_selection');
        return redirect(url_f('rank_table', clist => join ',', @clist));
    }

    return contests_new_frame
        if defined url_param('new') && $privs->{create_contests};

    try_contest_params_frame and return;

    my $ical = param('ical');
    my $json = param('json');
    return if $ical && $json;
    $p->{listview} = my $lv = CATS::ListView->new(name => 'contests',
        template => 'contests.' .  ($ical ? 'ics' : $json ? 'json' : 'html') . '.tt');

    CATS::UI::Prizes::contest_group_auto_new if defined param('create_group') && $is_root;

    contest_delete if url_param('delete');

    contests_new_save if defined param('new_save') && $privs->{create_contests};

    contests_edit_save
        if defined param('edit_save') &&
            get_registered_contestant(fields => 'is_jury', contest_id => param('id'));

    CATS::ContestParticipate::online if defined param('online_registration');

    my $vr = param('virtual_registration');
    CATS::ContestParticipate::virtual if defined $vr && $vr;

    contests_select_current if defined url_param('set_contest');

    $lv->define_columns(url_f('contests', has_problem => $p->{has_problem}), 1, 1, [
        { caption => res_str(601), order_by => '1 DESC, 2', width => '40%' },
        { caption => res_str(600), order_by => '1 DESC, 5', width => '15%' },
        { caption => res_str(631), order_by => '1 DESC, 6', width => '15%' },
        { caption => res_str(630), order_by => '1 DESC, 9', width => '30%' } ]);

    $settings->{contests}->{filter} = my $filter =
        param('filter') || $settings->{contests}->{filter} || 'unfinished';

    $lv->attach(url_f('contests'),
        defined $uid ? authenticated_contests_view($p) : anonymous_contests_view($p),
        ($uid ? () : { page_params => { filter => $filter } }));

    my $submenu = [
        map({
            href => url_f('contests', page => 0, filter => $_->{n}),
            item => res_str($_->{i}),
            selected => $settings->{contests}->{filter} eq $_->{n},
        }, { n => 'all', i => 558 }, { n => 'official', i => 559 }, { n => 'unfinished', i => 560 }),
        ($privs->{create_contests} ?
            { href => url_f('contests', new => 1), item => res_str(537) } : ()),
        { href => url_f('contests',
            ical => 1, rows => 50, filter => $filter), item => res_str(562) },
    ];
    $t->param(
        submenu => $submenu,
        authorized => defined $uid,
        href_contests => url_f('contests'),
        is_root => $is_root,
        is_registered => defined $uid && get_registered_contestant(contest_id => $cid) || 0,
    );
}

1;
