package CATS::UI::Contests;

use strict;
use warnings;

use CATS::Web qw(param param_on url_param redirect);
use CATS::DB;
use CATS::Constants;
use CATS::Misc qw(
    $t $is_jury $is_root $is_team $sid $cid $uid $contest $is_virtual $settings
    init_template init_listview_template msg res_str url_f auto_ext
    order_by define_columns attach_listview);
use CATS::Config qw(cats_dir);
use CATS::Utils qw(url_function coalesce date_to_iso);
use CATS::Data qw(:all);
use CATS::StaticPages;
use CATS::RankTable;

sub contests_new_frame
{
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

sub contest_checkbox_params()
{qw(
    free_registration run_all_tests
    show_all_tests show_test_resources show_checker_comment show_all_results
    is_official show_packages local_only is_hidden show_test_data
)}

sub contest_string_params()
{qw(
    contest_name start_date freeze_date finish_date open_date rules req_selection max_reqs
)}

sub get_contest_html_params
{
    my $p = {};

    $p->{$_} = scalar param($_) for contest_string_params();
    $p->{$_} = param_on($_) for contest_checkbox_params();

    $p->{contest_name} ne '' && length $p->{contest_name} < 100
        or return msg(27);

    $p;
}

sub register_contest_account
{
    my %p = @_;
    $p{$_} ||= 0 for (qw(is_jury is_pop is_hidden is_virtual diff_time));
    $p{$_} ||= 1 for (qw(is_ooc is_remote));
    $p{id} = new_id;
    my ($f, $v) = (join(', ', keys %p), join(',', map '?', keys %p));
    $dbh->do(qq~
        INSERT INTO contest_accounts ($f) VALUES ($v)~, undef,
        values %p);
    my $p = cats_dir() . "./rank_cache/$p{contest_id}#";
    unlink <$p*>;
}

sub contests_new_save
{
    my $p = get_contest_html_params() or return;

    my $cid = new_id;
    # free_registration => closed
    $p->{free_registration} = !$p->{free_registration};
    $dbh->do(qq~
        INSERT INTO contests (
            id, title, start_date, freeze_date, finish_date, defreeze_date, rules, req_selection, max_reqs,
            ctype,
            closed, run_all_tests, show_all_tests,
            show_test_resources, show_checker_comment, show_all_results,
            is_official, show_packages, local_only, is_hidden, show_frozen_reqs, show_test_data
        ) VALUES(
            ?, ?, ?, ?, ?, ?, ?, ?, ?,
            0,
            ?, ?, ?,
            ?, ?, ?,
            ?, ?, ?, ?, 0, ?)~,
        {},
        $cid, @$p{contest_string_params()},
        @$p{contest_checkbox_params()}
    );

    # Automatically register all admins as jury.
    my $root_accounts = $dbh->selectcol_arrayref(qq~
        SELECT id FROM accounts WHERE srole = ?~, undef, $cats::srole_root);
    push @$root_accounts, $uid unless $is_root; # User with contests_creator role.
    for (@$root_accounts)
    {
        register_contest_account(
            contest_id => $cid, account_id => $_,
            is_jury => 1, is_pop => 1, is_hidden => 1);
    }
    $dbh->commit;
}

sub try_contest_params_frame
{
    my $id = url_param('params') or return;

    init_template('contest_params.html.tt');

    my $p = $dbh->selectrow_hashref(qq~
        SELECT
            title AS contest_name,
            start_date,
            freeze_date,
            finish_date,
            defreeze_date AS open_date,
            1 - closed AS free_registration,
            run_all_tests, show_all_tests, show_test_resources, show_checker_comment, show_test_data,
            show_all_results, is_official, show_packages, local_only, rules, req_selection,
            is_hidden, max_reqs
        FROM contests WHERE id = ?~, { Slice => {} },
        $id
    ) or return;
    $t->param(
        id => $id, %$p,
        href_action => url_f('contests'),
        can_edit => (get_registered_contestant(fields => 'is_jury', contest_id => $id) ? 1 : 0),
    );

    1;
}

sub contests_edit_save
{
    my $edit_cid = param('id');

    my $p = get_contest_html_params() or return;

    # free_registration => closed
    $p->{free_registration} = !$p->{free_registration};
    eval {
        $dbh->do(qq~
            UPDATE contests SET
                title=?, start_date=?, freeze_date=?,
                finish_date=?, defreeze_date=?, rules=?, req_selection=?, max_reqs=?,
                closed=?, run_all_tests=?, show_all_tests=?,
                show_test_resources=?, show_checker_comment=?, show_all_results=?,
                is_official=?, show_packages=?,
                local_only=?, is_hidden=?, show_frozen_reqs=0, show_test_data=?
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
    # Change page title immediately if the current contest is renamed.
    if ($edit_cid == $cid) {
        $contest->{title} = Encode::decode_utf8($p->{contest_name});
    }
    msg(1036);
}

sub contest_online_registration
{
    !get_registered_contestant(contest_id => $cid)
        or return msg(111);

    if ($is_root)
    {
        register_contest_account(
            contest_id => $cid, account_id => $uid,
            is_jury => 1, is_pop => 1, is_hidden => 1);
    }
    else
    {
        $contest->{time_since_finish} <= 0 or return msg(108);
        !$contest->{closed} or return msg(105);
        register_contest_account(contest_id => $cid, account_id => $uid);
    }
    $dbh->commit;
}

sub contest_virtual_registration
{
    my ($registered, $is_virtual, $is_remote) = get_registered_contestant(
         fields => '1, is_virtual, is_remote', contest_id => $cid);

    !$registered || $is_virtual
        or return msg(114);

    $contest->{time_since_start} >= 0
        or return msg(109);

    # In official contests, virtual participation is allowed only after the finish.
    $contest->{time_since_finish} >= 0 || !$contest->{is_official}
        or return msg(122);

    !$contest->{closed}
        or return msg(105);

    # Repeat virtual registration removes old results.
    if ($registered)
    {
        $dbh->do(qq~
            DELETE FROM reqs WHERE account_id = ? AND contest_id = ?~, undef,
            $uid, $cid);
        $dbh->do(qq~
            DELETE FROM contest_accounts WHERE account_id = ? AND contest_id = ?~, undef,
            $uid, $cid);
        $dbh->commit;
        msg(113);
    }

    register_contest_account(
        contest_id => $cid, account_id => $uid,
        is_virtual => 1, is_remote => $is_remote,
        diff_time => $contest->{time_since_start});
    $dbh->commit;
}

sub contests_select_current
{
    defined $uid or return;

    my ($registered, $is_virtual, $is_jury) = get_registered_contestant(
        fields => '1, is_virtual, is_jury', contest_id => $cid
    );
    return if $is_jury;

    $t->param(selected_contest_title => $contest->{title});

    if ($contest->{time_since_finish} > 0)
    {
        msg(115);
    }
    elsif (!$registered)
    {
        msg(1116);
    }
}

sub common_contests_view ($)
{
    my ($c) = @_;
    return (
        id => $c->{id},
        contest_name => $c->{title},
        start_date => $c->{start_date},
        start_date_iso => date_to_iso($c->{start_date}),
        finish_date => $c->{finish_date},
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

sub contest_fields ()
{
    # HACK: starting page is a contests list, displayed very frequently.
    # In the absense of a filter, select only the first page + 1 record.
    # my $s = $settings->{$listview_name};
    # (($s->{page} || 0) == 0 && !$s->{search} ? 'FIRST ' . ($s->{rows} + 1) : '') .
    q~c.ctype, c.id, c.title,
    c.start_date, c.finish_date, c.freeze_date, c.defreeze_date, c.closed, c.is_official, c.rules~
}

sub contests_submenu_filter
{
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

sub authenticated_contests_view ()
{
    my $cf = contest_fields();
    my $has_problem = param('has_problem');
    my $original_contest = 0;
    if ($has_problem) {
        ($original_contest, my $title) = $dbh->selectrow_array(q~
            SELECT P.contest_id, P.title FROM problems P WHERE P.id = ?~, undef, $has_problem);
        if ($original_contest) {
            msg(1015, $title);
        }
        else {
            $has_problem = 0;
        }
    }
    my $sth = $dbh->prepare(qq~
        SELECT
            $cf, CA.is_virtual, CA.is_jury, CA.id AS registered, C.is_hidden
        FROM contests C LEFT JOIN
            contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        WHERE
            (CA.account_id IS NOT NULL OR COALESCE(C.is_hidden, 0) = 0) ~ .
            ($has_problem ? q~AND EXISTS (
                SELECT 1 FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.problem_id = ?) ~ : contests_submenu_filter()) .
            order_by);
    $sth->execute($uid, $has_problem ? $has_problem : ());

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

sub anonymous_contests_view ()
{
    my $cf = contest_fields();
    my $sth = $dbh->prepare(qq~
        SELECT $cf FROM contests C WHERE COALESCE(C.is_hidden, 0) = 0 ~ .
        contests_submenu_filter() . order_by
    );
    $sth->execute;

    my $fetch_contest = sub($)
    {
        my $c = $_[0]->fetchrow_hashref or return;
        return common_contests_view($c);
    };
    return ($fetch_contest, $sth);
}

sub contests_frame
{
    if (defined param('summary_rank'))
    {
        my @clist = param('contests_selection');
        return redirect(url_f('rank_table', clist => join ',', @clist));
    }

    return contests_new_frame
        if defined url_param('new') && $CATS::Misc::can_create_contests;

    try_contest_params_frame and return;

    my $ical = param('ical');
    my $json = param('json');
    return if $ical && $json;
    init_listview_template('contests', 'contests',
        'contests.' .  ($ical ? 'ics' : $json ? 'json' : 'html') . '.tt');

    CATS::UI::Prizes::contest_group_auto_new if defined param('create_group') && $is_root;

    if (defined url_param('delete') && $is_root) {
        my $cid = url_param('delete');
        $dbh->do(qq~DELETE FROM contests WHERE id = ?~, {}, $cid);
        $dbh->commit;
        msg(1037);
    }

    contests_new_save if defined param('new_save') && $CATS::Misc::can_create_contests;

    contests_edit_save
        if defined param('edit_save') &&
            get_registered_contestant(fields => 'is_jury', contest_id => param('id'));

    contest_online_registration if defined param('online_registration');

    my $vr = param('virtual_registration');
    contest_virtual_registration if defined $vr && $vr;

    contests_select_current if defined url_param('set_contest');

    define_columns(url_f('contests'), 1, 1, [
        { caption => res_str(601), order_by => '1 DESC, 2', width => '40%' },
        { caption => res_str(600), order_by => '1 DESC, 4', width => '15%' },
        { caption => res_str(631), order_by => '1 DESC, 5', width => '15%' },
        { caption => res_str(630), order_by => '1 DESC, 8', width => '30%' } ]);

    $_ = coalesce(param('filter'), $_, 'unfinished') for $settings->{contests}->{filter};

    attach_listview(url_f('contests'),
        defined $uid ? authenticated_contests_view : anonymous_contests_view,
        ($uid ? () : { page_params => { filter => $settings->{contests}->{filter} } }));

    my $submenu = [
        map({
            href => url_f('contests', page => 0, filter => $_->{n}),
            item => res_str($_->{i}),
            selected => $settings->{contests}->{filter} eq $_->{n},
        }, { n => 'all', i => 558 }, { n => 'official', i => 559 }, { n => 'unfinished', i => 560 }),
        ($CATS::Misc::can_create_contests ?
            { href => url_f('contests', new => 1), item => res_str(537) } : ()),
        { href => url_f('contests',
            ical => 1, rows => 50, filter => $settings->{contests}->{filter}), item => res_str(562) },
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
