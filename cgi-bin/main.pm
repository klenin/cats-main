#!/usr/bin/perl
package main;

use strict;
use warnings;
use encoding 'utf8', STDIN => undef;

use Encode;

use Data::Dumper;
use Storable ();
use Time::HiRes;

our $cats_lib_dir;
BEGIN {
    $cats_lib_dir = $ENV{CATS_DIR} || '.';
    $cats_lib_dir =~ s/\/$//;
    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 1;
    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT_OK = qw(
        handler
        );
    our %EXPORT_TAGS = (all => [@EXPORT_OK]);
}
use lib $cats_lib_dir;


use CATS::Web qw(param url_param save_uploaded_file redirect upload_source init_request get_return_code);
use CATS::DB;
use CATS::Constants;
use CATS::BinaryFile;
use CATS::DevEnv;
use CATS::Misc qw(:all);
use CATS::Utils qw(coalesce escape_html url_function state_to_display param_on);
use CATS::Data qw(:all);
use CATS::IP;
use CATS::Problem;
use CATS::Problem::Text;
use CATS::RankTable;
use CATS::StaticPages;
use CATS::TeX::Lite;
use CATS::Testset;
use CATS::Contest::Results;
use CATS::User;
use CATS::Console;
use CATS::RunDetails;
use CATS::Prizes;
use CATS::Messages;
use CATS::Stats;
use CATS::Judges;
use CATS::Compilers;
use CATS::Keywords;

sub make_sid {
    my @ch = ('A'..'Z', 'a'..'z', '0'..'9');
    join '', map { $ch[rand @ch] } 1..30;
}


sub login_frame
{
    my $json = param('json');
    init_template(auto_ext('login', $json));
    $t->param(href_login => url_function('login'));
    msg(1004) if param('logout');

    my $login = param('login');
    if (!$login) {
        $t->param(message => 'No login') if $json;
        return;
    }
    $t->param(login => Encode::decode_utf8($login));
    my $passwd = param('passwd');

    my ($aid, $passwd2, $locked) = $dbh->selectrow_array(qq~
        SELECT id, passwd, locked FROM accounts WHERE login = ?~, undef, $login);

    $aid && $passwd2 eq $passwd or return msg(40);
    !$locked or msg(41);

    my $last_ip = CATS::IP::get_ip();

    my $cid = url_param('cid');
    for (1..20) {
        $sid = make_sid;

        $dbh->do(qq~
            UPDATE accounts SET sid = ?, last_login = CURRENT_TIMESTAMP, last_ip = ?
                WHERE id = ?~,
            {}, $sid, $last_ip, $aid
        ) or next;
        $dbh->commit;

        if ($json) {
            $contest->load($cid, ['id']);
            $t->param(sid => $sid, cid => $contest->{id});
            return;
        }
        $t = undef;
        return redirect(url_function('contests', sid => $sid, cid => $cid));
    }
    die 'Can not generate sid';
}


sub logout_frame
{
    $cid = '';
    $sid = '';
    if ($uid) {
        $dbh->do(qq~UPDATE accounts SET sid = NULL WHERE id = ?~, {}, $uid);
        $dbh->commit;
    }
    if (param('json')) {
        init_template(auto_ext('logout'));
        0;
    }
    else {
       redirect(url_function('login', logout => 1));
    }
}


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
    is_official show_packages local_only is_hidden
)}


sub contest_string_params()
{qw(
    contest_name start_date freeze_date finish_date open_date rules max_reqs
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
            id, title, start_date, freeze_date, finish_date, defreeze_date, rules, max_reqs,
            ctype,
            closed, run_all_tests, show_all_tests,
            show_test_resources, show_checker_comment, show_all_results,
            is_official, show_packages, local_only, is_hidden, show_frozen_reqs
        ) VALUES(
            ?, ?, ?, ?, ?, ?, ?, ?,
            0,
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)~,
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
            run_all_tests, show_all_tests, show_test_resources, show_checker_comment,
            show_all_results, is_official, show_packages, local_only, rules, is_hidden, max_reqs
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
    $dbh->do(qq~
        UPDATE contests SET
            title=?, start_date=?, freeze_date=?,
            finish_date=?, defreeze_date=?, rules=?, max_reqs=?,
            closed=?, run_all_tests=?, show_all_tests=?,
            show_test_resources=?, show_checker_comment=?, show_all_results=?,
            is_official=?, show_packages=?,
            local_only=?, is_hidden=?, show_frozen_reqs=0
        WHERE id=?~,
        {},
        @$p{contest_string_params()},
        @$p{contest_checkbox_params()},
        $edit_cid
    );
    $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(cid => $edit_cid, all => 1);
    CATS::RankTable::remove_cache($edit_cid);
    # Change page title immediately if the current contest is renamed.
    if ($edit_cid == $cid) {
        $contest->{title} = Encode::decode_utf8($p->{contest_name});
    }
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
        msg(116);
    }
}

sub date_to_iso {
    $_[0] =~ /^\s*(\d+)\.(\d+)\.(\d+)\s+(\d+):(\d+)\s*$/;
    "$3$2$1T$4${5}00";
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
       registration_denied => $c->{closed},
       selected => $c->{id} == $cid,
       is_official => $c->{is_official},
       show_points => $c->{rules},
       href_contest => url_function('contests', sid => $sid, set_contest => 1, cid => $c->{id}),
       href_params => url_f('contests', params => $c->{id}),
    );
}

sub contest_fields ()
{
    # HACK: starting page is a contests list, displayed very frequently.
    # In the absense of a filter, select only the first page + 1 record.
    # my $s = $settings->{$listview_name};
    # (($s->{page} || 0) == 0 && !$s->{search} ? 'FIRST ' . ($s->{rows} + 1) : '') .
    q~c.ctype, c.id, c.title,
    c.start_date, c.finish_date, c.closed, c.is_official, c.rules~
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
    my $has_problem_orig = $has_problem ?
        '(SELECT 1 FROM problems P WHERE P.contest_id = C.id AND P.id = ?)' : '0';
    my $sth = $dbh->prepare(qq~
        SELECT
            $cf, CA.is_virtual, CA.is_jury, CA.id AS registered, C.is_hidden,
            $has_problem_orig AS has_orig
        FROM contests C LEFT JOIN
            contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        WHERE
            (CA.account_id IS NOT NULL OR COALESCE(C.is_hidden, 0) = 0) ~ .
            ($has_problem ? q~AND EXISTS (
                SELECT 1 FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.problem_id = ?) ~ : contests_submenu_filter()) .
            order_by);
    $sth->execute($has_problem ? ($has_problem, $uid, $has_problem) : ($uid));

    my $fetch_contest = sub($)
    {
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
            has_orig => $c->{has_orig},
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

    CATS::Prizes::contest_group_auto_new if defined param('create_group') && $is_root;

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


sub problems_change_status ()
{
    my $cpid = param('change_status')
        or return msg(54);

    my $new_status = param('status');
    exists problem_status_names()->{$new_status} or return;

    $dbh->do(qq~
        UPDATE contest_problems SET status = ? WHERE contest_id = ? AND id = ?~, {},
        $new_status, $cid, $cpid);
    $dbh->commit;
    # Perhaps a 'hidden' status changed.
    CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $cpid);
}

sub problems_change_code ()
{
    my $cpid = param('change_code')
        or return msg(54);
    my $new_code = param('code') || '';
    cats::is_good_problem_code($new_code) or return msg(1134);
    $dbh->do(qq~
        UPDATE contest_problems SET code = ? WHERE contest_id = ? AND id = ?~, {},
        $new_code, $cid, $cpid);
    $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $cpid);
}

sub add_problem_to_contest
{
    my ($pid, $problem_code) = @_;
    CATS::StaticPages::invalidate_problem_text(cid => $cid);
    $dbh->selectrow_array(q~
        SELECT 1 FROM contest_problems WHERE contest_id = ? and problem_id = ?~, undef,
        $cid, $pid) and return msg(1003);
    $dbh->do(qq~
        INSERT INTO contest_problems(id, contest_id, problem_id, code, status)
            VALUES (?, ?, ?, ?, ?)~, {},
        new_id, $cid, $pid, $problem_code,
        # If non-archive contest is in progress, hide newly added problem immediately.
        $contest->{time_since_start} > 0 && $contest->{ctype} == 0 ?
            $cats::problem_st_hidden : $cats::problem_st_ready);
}

sub problems_link_save
{
    my $pid = param('problem_id')
        or return msg(104);

    my $problem_code;
    if (!$contest->is_practice) {
        $problem_code = param('problem_code');
        cats::is_good_problem_code($problem_code) or return msg(1134);
    }
    my $move_problem = param('move');
    if ($move_problem) {
        # Нужны права жюри в турнире, из которого перемещаем задачу
        # Проверим заранее, чтобы не нужно было делать rollback
        my ($j) = $dbh->selectrow_array(q~
            SELECT CA.is_jury FROM contest_accounts CA
                INNER JOIN contests C ON CA.contest_id = C.id
                INNER JOIN problems P ON C.id = P.contest_id
            WHERE CA.account_id = ? AND P.id = ?~, undef,
            $uid, $pid);
        $j or return msg(135);
    }
    add_problem_to_contest($pid, $problem_code) or return;
    if ($move_problem) {
        $dbh->do(q~
            UPDATE problems SET contest_id = ? WHERE id = ?~, undef,
            $cid, $pid);
    }
    else {
        msg(1001);
    }
    $dbh->commit;
}


sub problems_replace
{
    my $pid = param('problem_id')
        or return msg(54);
    my $file = param('zip') || '';
    $file =~ /\.(zip|ZIP)$/
        or return msg(53);
    my ($contest_id, $old_title) = $dbh->selectrow_array(qq~
        SELECT contest_id, title FROM problems WHERE id=?~, {}, $pid);
    # Запрет на замену прилинкованных задач. Во-первых, для надёжности,
    # а во-вторых, это секурити -- чтобы не проверять is_jury($contest_id).
    $contest_id == $cid
        or return msg(117);
    my $fname = save_uploaded_file('zip');

    my CATS::Problem $p = CATS::Problem->new;
    $p->{old_title} = $old_title unless param('allow_rename');
    my $error = $p->load($fname, $cid, $pid, 1);
    $t->param(problem_import_log => $p->encoded_import_log());
    #unlink $fname;
    if ($error) {
        $dbh->rollback;
        return msg(1008);
    }
    $dbh->do(q~
        UPDATE contest_problems SET max_points = NULL WHERE problem_id = ?~, undef, $pid);
    $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(pid => $pid);
    msg(1007);
}


sub problems_add_new
{
    my $file = param('zip') || '';
    $file =~ /\.(zip|ZIP)$/
        or return msg(53);
    my $fname = save_uploaded_file('zip');

    my $problem_code;
    if (!$contest->is_practice) {
        ($problem_code) = $contest->unused_problem_codes
            or return msg(1017);
    }

    my CATS::Problem $p = CATS::Problem->new;
    my $error = $p->load($fname, $cid, new_id, 0);
    $t->param(problem_import_log => $p->encoded_import_log());
    $error ||= !add_problem_to_contest($p->{id}, $problem_code);

    $error ? $dbh->rollback : $dbh->commit;
    msg(1008) if $error;
    unlink $fname;
}


sub problems_all_frame
{
    init_listview_template('link_problem', 'link_problem', 'problems_link.html.tt');

    my $link = url_param('link');
    my $kw = url_param('kw');
    my $move = url_param('move') || 0;

    if ($link) {
        my @u = $contest->unused_problem_codes
            or return msg(1017);
        $t->param(unused_codes => [ @u ]);
    }

    my $cols = [
        { caption => res_str(602), order_by => '2', width => '30%' },
        { caption => res_str(603), order_by => '3', width => '30%' },
        { caption => res_str(604), order_by => '4', width => '10%' },
        #{ caption => res_str(605), order_by => '5', width => '10%' },
    ];
    define_columns(url_f('problems', link => $link, kw => $kw), 0, 0, $cols);

    my $where =
        $is_root ? {
            cond => [], 'params' => [] }
        : !$link ? {
            cond => ['CURRENT_TIMESTAMP > C.finish_date AND (C.is_hidden = 0 OR C.is_hidden IS NULL)'],
            'params' => [] }
        : {
            cond => [q~
            (
                EXISTS (
                    SELECT 1 FROM contest_accounts
                    WHERE contest_id = C.id AND account_id = ? AND is_jury = 1
                    ) OR CURRENT_TIMESTAMP > C.finish_date AND (C.is_hidden = 0 OR C.is_hidden IS NULL)
            )~],
            params => [$uid]
        };

    if ($kw) {
        push @{$where->{cond}}, q~
            (EXISTS (SELECT 1 FROM problem_keywords PK WHERE PK.problem_id = P.id AND PK.keyword_id = ?))~;
        push @{$where->{params}}, $kw;
    }

    my $where_cond = join(' AND ', @{$where->{cond}}) || '1=1';
    my $c = $dbh->prepare(qq~
        SELECT P.id, P.title, C.title, C.id,
            (SELECT
                SUM(CASE R.state WHEN $cats::st_accepted THEN 1 ELSE 0 END) || ' / ' ||
                SUM(CASE R.state WHEN $cats::st_wrong_answer THEN 1 ELSE 0 END) || ' / ' ||
                SUM(CASE R.state WHEN $cats::st_time_limit_exceeded THEN 1 ELSE 0 END)
                FROM reqs R WHERE R.problem_id = P.id
            ),
            (SELECT COUNT(*) FROM contest_problems CP WHERE CP.problem_id = P.id AND CP.contest_id = ?)
        FROM problems P INNER JOIN contests C ON C.id = P.contest_id
        WHERE $where_cond ~ . order_by);
    $c->execute($cid, @{$where->{params}});

    my $fetch_record = sub($)
    {
        my ($pid, $problem_name, $contest_name, $contest_id, $counts, $linked) = $_[0]->fetchrow_array
            or return ();
        return (
            href_view_problem => url_f('problem_text', pid => $pid),
            href_view_contest => url_function('problems', sid => $sid, cid => $contest_id),
            linked => $linked || !$link,
            problem_id => $pid,
            problem_name => $problem_name,
            contest_name => $contest_name,
            counts => $counts,
        );
    };

    attach_listview(url_f('problems', link => $link, kw => $kw, move => $move), $fetch_record, $c);

    $t->param(
        href_action => url_f($kw ? 'keywords' : 'problems'),
        link => !$contest->is_practice && $link, move => $move, is_jury => $is_jury);

    $c->finish;
}


sub download_problem
{
    my $pid = param('download');
    # If hash is non-empty, redirect to existing file.
    # Package size is supposed to be large enough to warrant a separate query.
    my ($hash, $status) = $dbh->selectrow_array(qq~
        SELECT P.hash, CP.status FROM problems P
        INNER JOIN contest_problems CP ON cp.problem_id = P.id
        WHERE CP.contest_id = ? AND P.id = ?~, undef,
        $cid, $pid);
    defined $status && ($is_jury || $status != $cats::problem_st_hidden)
        or return;
    undef $t;
    my $already_hashed = ensure_problem_hash($pid, \$hash);
    my $fname = "./download/pr/problem_$hash.zip";
    unless($already_hashed && -f $fname)
    {
        my ($zip) = eval { $dbh->selectrow_array(qq~
            SELECT zip_archive FROM problems WHERE id = ?~, undef, $pid); };
        if ($@)
        {
            print header(), $@;
            return;
        }
        CATS::BinaryFile::save(cats_dir() . $fname, $zip);
    }
    redirect($fname);
}


sub can_upsolve
{
    my ($tag) = $dbh->selectrow_array(q~
         SELECT CA.tag FROM contest_accounts CA
             WHERE CA.contest_id = ? AND CA.account_id = ?~, undef,
         $cid, $uid || 0);
    !!(($tag || '') =~ /upsolve/);
}


sub problem_submit_too_frequent
{
    my ($submit_uid) = @_;
    # Protect from Denial of Service -- disable too frequent submissions.
    my $prev = $dbh->selectcol_arrayref(q~
        SELECT FIRST 2 CAST(CURRENT_TIMESTAMP - R.submit_time AS DOUBLE PRECISION) FROM reqs R
        WHERE R.account_id = ?
        ORDER BY R.submit_time DESC~, {},
        $submit_uid);
    my $SECONDS_PER_DAY = 24 * 60 * 60;
    ($prev->[0] || 1) < 3/$SECONDS_PER_DAY || ($prev->[1] || 1) < 60/$SECONDS_PER_DAY;
}


sub problems_submit
{
    my $pid = param('problem_id')
        or return msg(1012);

    my $file = param('source') // '';
    $file ne '' || param('source_text') ne '' or return msg(1009);
    length($file) <= 200 or return msg(1010);

    defined param('de_id') or return msg(1013);

    my $time_since_finish = 0;
    unless ($is_jury) {
        (my $time_since_start, $time_since_finish, my $is_official, my $status) = $dbh->selectrow_array(qq~
            SELECT
                CAST(CURRENT_TIMESTAMP - $virtual_diff_time - C.start_date AS DOUBLE PRECISION),
                CAST(CURRENT_TIMESTAMP- $virtual_diff_time - C.finish_date AS DOUBLE PRECISION),
                C.is_official, CP.status
            FROM contests C, contest_problems CP
            WHERE CP.contest_id = C.id AND C.id = ? AND CP.problem_id = ?~, {},
            $cid, $pid);

        $time_since_start >= 0
            or return msg(80);
        $time_since_finish <= 0 || $is_virtual || can_upsolve
            or return msg(81);
        !defined $status || $status < $cats::problem_st_disabled
            or return msg(124);

        # During the official contest, do not accept submissions for other contests.
        if (!$is_official || $is_virtual) {
            my ($current_official) = $contest->current_official;
            !$current_official
                or return msg(123, $current_official->{title});
        }
    }

    my $submit_uid = $uid // ($contest->is_practice ? get_anonymous_uid() : die);

    return msg(131) if problem_submit_too_frequent($submit_uid);

    my $prev_reqs_count;
    if ($contest->{max_reqs} && !$is_jury) {
        $prev_reqs_count = $dbh->selectrow_array(q~
            SELECT COUNT(*) FROM reqs R
            WHERE R.account_id = ? AND R.problem_id = ? AND R.contest_id = ?~, {},
            $submit_uid, $pid, $cid);
        return msg(137) if $prev_reqs_count >= $contest->{max_reqs};
    }

    my $src = param('source_text') || upload_source('source');
    defined $src or return msg(1010);
    $src ne '' or return msg(1011);
    my $did = param('de_id');

    if ($did eq 'by_extension') {
        my $de_list = CATS::DevEnv->new($dbh, active_only => 1);
        my $de = $de_list->by_file_extension($file)
            or return msg(1013);
        $did = $de->{id};
        $t->param(de_name => $de->{description});
    }

    # Forbid repeated submissions of the identical code with the same DE.
    my $source_hash = CATS::Utils::source_hash($src);
    my ($same_source) = $dbh->selectrow_array(qq~
        SELECT FIRST 1 S.req_id
        FROM sources S INNER JOIN reqs R ON S.req_id = R.id
        WHERE
            R.account_id = ? AND R.problem_id = ? AND
            R.contest_id = ? AND S.hash = ? AND S.de_id = ?~, {},
        $submit_uid, $pid, $cid, $source_hash, $did);
    $same_source and return msg(132);

    my $rid = new_id;

    $dbh->do(qq~
        INSERT INTO reqs (
            id, account_id, problem_id, contest_id,
            submit_time, test_time, result_time, state, received
        ) VALUES (
            ?,?,?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,?,?)~,
        {},
        $rid, $submit_uid, $pid, $cid, $cats::st_not_processed, 0);

    my $s = $dbh->prepare(qq~
        INSERT INTO sources(req_id, de_id, src, fname, hash) VALUES (?,?,?,?,?)~);
    $s->bind_param(1, $rid);
    $s->bind_param(2, $did);
    $s->bind_param(3, $src, { ora_type => 113 } ); # blob
    $s->bind_param(4, $file ? "$file" :
        "$rid." . CATS::DevEnv->new($dbh, id => $did)->default_extension($did));
    $s->bind_param(5, $source_hash);
    $s->execute;
    $dbh->commit;

    $t->param(solution_submitted => 1, href_console => url_f('console'));
    $time_since_finish > 0 ? msg(87) :
    defined $prev_reqs_count ? msg(88, $contest->{max_reqs} - $prev_reqs_count - 1) :
    msg(1014);
}


sub problems_submit_std_solution
{
    my $pid = param('problem_id');

    defined $pid or return msg(1012);

    my $ok = 0;

    my $c = $dbh->prepare(qq~
        SELECT src, de_id, fname
        FROM problem_sources
        WHERE problem_id = ? AND (stype = ? OR stype = ?)~);
    $c->execute($pid, $cats::solution, $cats::adv_solution);

    while (my ($src, $did, $fname) = $c->fetchrow_array)
    {
        my $rid = new_id;

        $dbh->do(qq~
            INSERT INTO reqs(
                id, account_id, problem_id, contest_id,
                submit_time, test_time, result_time, state, received
            ) VALUES (
                ?, ?, ?, ?,
                CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?, 0)~,
            {}, $rid, $uid, $pid, $cid, $cats::st_not_processed
        );

        my $s = $dbh->prepare(qq~
            INSERT INTO sources(req_id, de_id, src, fname) VALUES (?, ?, ?, ?)~);
        $s->bind_param(1, $rid);
        $s->bind_param(2, $did);
        $s->bind_param(3, $src, { ora_type => 113 } ); # blob
        $s->bind_param(4, $fname);
        $s->execute;

        $ok = 1;
    }

    if ($ok)
    {
        $dbh->commit;
        $t->param(solution_submitted => 1, href_console => url_f('console'));
        msg(107);
    }
    else
    {
        msg(106);
    }
}


sub problems_mass_retest()
{
    my @retest_pids = param('problem_id') or return msg(1012);
    my $all_runs = param('all_runs');
    my $count = 0;
    for my $retest_pid (@retest_pids)
    {
        my $runs = $dbh->selectall_arrayref(q~
            SELECT id, account_id, state FROM reqs
            WHERE contest_id = ? AND problem_id = ? ORDER BY id DESC~,
            { Slice => {} },
            $cid, $retest_pid
        );
        my %accounts = ();
        for (@$runs)
        {
            next if !$all_runs && $accounts{$_->{account_id}};
            $accounts{$_->{account_id}} = 1;
            ($_->{state} || 0) != $cats::st_ignore_submit &&
                enforce_request_state(request_id => $_->{id}, state => $cats::st_not_processed)
                    and ++$count;
        }
        $dbh->commit;
    }
    return msg(128, $count);
}


sub problems_recalc_points()
{
    my @pids = param('problem_id') or return msg(1012);
    $dbh->do(q~
        UPDATE reqs SET points = NULL
        WHERE contest_id = ? AND problem_id IN (~ . join(',', @pids) . q~)~, undef,
        $cid);
    $dbh->commit;
    CATS::RankTable::remove_cache($cid);
}


sub problems_frame_jury_action
{
    $is_jury or return;

    defined param('link_save') and return problems_link_save;
    defined param('change_status') and return problems_change_status;
    defined param('change_code') and return problems_change_code;
    defined param('replace') and return problems_replace;
    defined param('add_new') and return problems_add_new;
    defined param('std_solution') and return problems_submit_std_solution;
    defined param('mass_retest') and return problems_mass_retest;
    my $cpid = url_param('delete');
    CATS::Problem::delete($cpid) if $cpid;
}


sub problem_select_testsets
{
    init_template('problem_select_testsets.html.tt');
    my $cpid = param('cpid') or return;

    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.id, P.title, CP.id AS cpid, CP.contest_id, CP.testsets, CP.points_testsets
        FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE CP.id = ?~, undef,
        $cpid) or return;
    is_jury_in_contest(contest_id => $problem->{contest_id}) or return;

    my $testsets = $dbh->selectall_arrayref(q~
        SELECT * FROM testsets WHERE problem_id = ? ORDER BY name~, { Slice => {} },
        $problem->{id});

    my $param_to_list = sub {
        my %sel;
        @sel{param($_[0])} = undef;
        join ',', map $_->{name}, grep exists $sel{$_->{id}}, @$testsets;
    };
    if (param('save')) {
        $dbh->do(q~
            UPDATE contest_problems SET testsets = ?, points_testsets = ?, max_points = NULL
            WHERE id = ?~, undef,
            map($param_to_list->("sel_$_"), qw(testsets points_testsets)), $problem->{cpid});
        $dbh->commit;
        return redirect(url_f('problems'));
    }

    my $list_to_selected = sub {
        my %sel;
        @sel{split ',', $problem->{$_[0]} || ''} = undef;
        $_->{"sel_$_[0]"} = exists $sel{$_->{name}} for @$testsets;
    };
    $list_to_selected->($_) for qw(testsets points_testsets);

    $t->param("problem_$_" => $problem->{$_}) for keys %$problem;
    $t->param(testsets => $testsets, href_select_testsets => url_f('problem_select_testsets'));
}


sub problems_retest_frame
{
    $is_jury && !$contest->is_practice or return;
    init_listview_template('problems_retest', 'problems', 'problems_retest.html.tt');

    defined param('mass_retest') and problems_mass_retest;
    defined param('recalc_points') and problems_recalc_points;

    my @cols = (
        { caption => res_str(602), order_by => '3', width => '30%' }, # name
        { caption => res_str(639), order_by => '7', width => '10%' }, # in queue
        { caption => res_str(622), order_by => '6', width => '10%' }, # status
        { caption => res_str(605), order_by => '5', width => '10%' }, # testset
        { caption => res_str(604), order_by => '8', width => '10%' }, # ok/wa/tl
    );
    define_columns(url_f('problems_retest'), 0, 0, [ @cols ]);
    my $reqs_count_sql = 'SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state =';
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            CP.code, P.title AS problem_name, CP.testsets, CP.points_testsets, CP.status,
            ($reqs_count_sql $cats::st_accepted) AS accepted_count,
            ($reqs_count_sql $cats::st_wrong_answer) AS wrong_answer_count,
            ($reqs_count_sql $cats::st_time_limit_exceeded) AS time_limit_count,
            (SELECT COUNT(*) FROM reqs R
                WHERE R.contest_id = CP.contest_id AND R.problem_id = CP.problem_id AND
                R.state < $cats::request_processed) AS in_queue
        FROM problems P INNER JOIN contest_problems CP ON CP.problem_id = P.id
        WHERE CP.contest_id = ?~ . order_by);
    $sth->execute($cid);

    my $total_queue = 0;
    my $fetch_record = sub($)
    {
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
        my $psn = problem_status_names();
        $total_queue += $c->{in_queue};
        return (
            status => $psn->{$c->{status}},
            href_view_problem => url_f('problem_text', cpid => $c->{cpid}),
            problem_id => $c->{pid},
            code => $c->{code},
            problem_name => $c->{problem_name},
            accept_count => $c->{accepted_count},
            wa_count => $c->{wrong_answer_count},
            tle_count => $c->{time_limit_count},
            testsets => $c->{testsets} || '*',
            points_testsets => $c->{points_testsets},
            in_queue => $c->{in_queue},
            href_select_testsets => url_f('problem_select_testsets', cpid => $c->{cpid}),
        );
    };
    attach_listview(url_f('problems_retest'), $fetch_record, $sth);

    $sth->finish;

    $t->param(total_queue => $total_queue);
}


sub problems_frame
{
    my $my_is_team =
        $is_jury || $contest->is_practice ||
        $is_team && ($contest->{time_since_finish} - $virtual_diff_time < 0 || can_upsolve);
    my $show_packages = 1;
    unless ($is_jury)
    {
        $show_packages = $contest->{show_packages};
        my $local_only = $contest->{local_only};
        if ($contest->{time_since_start} < 0)
        {
            init_template('problems_inaccessible.html.tt');
            return msg(130);
        }
        if ($local_only)
        {
            my ($is_remote, $is_ooc);
            if ($uid)
            {
                ($is_remote, $is_ooc) = $dbh->selectrow_array(qq~
                    SELECT is_remote, is_ooc FROM contest_accounts WHERE contest_id = ? AND account_id = ?~,
                    {}, $cid, $uid);
            }
            if ((!defined $is_remote || $is_remote) && (!defined $is_ooc || $is_ooc))
            {
                init_template('problems_inaccessible.html.tt');
                return msg(129);
            }
        }
    }

    $is_jury && defined url_param('link') and return problems_all_frame;
    defined url_param('kw') and return problems_all_frame;

    init_listview_template('problems' . ($contest->is_practice ? '_practice' : ''),
        'problems', auto_ext('problems'));
    defined param('download') && $show_packages and return download_problem;
    problems_frame_jury_action;

    problems_submit if defined param('submit');

    my @cols = (
        { caption => res_str(602), order_by => ($contest->is_practice ? '4' : '3'), width => '30%' },
        ($is_jury ?
        (
            { caption => res_str(622), order_by => '11', width => '10%' }, # status
            { caption => res_str(605), order_by => '15', width => '10%' }, # tests set
            { caption => res_str(635), order_by => '13', width => '5%' }, # modified by
            { caption => res_str(634), order_by => 'P.upload_date', width => '10%' }, # modification date
        )
        : ()
        ),
        ($contest->is_practice ?
        { caption => res_str(603), order_by => '5', width => '20%' } : ()
        ),
        { caption => res_str(604), order_by => '6', width => '10%' },
    );
    define_columns(url_f('problems'), 0, 0, \@cols);

    my $reqs_count_sql = 'SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state =';
    my $account_condition = $contest->is_practice ? '' : ' AND D.account_id = ?';
    my $select_code = $contest->is_practice ? 'NULL' : 'CP.code';
    my $hidden_problems = $is_jury ? '' : " AND (CP.status IS NULL OR CP.status < $cats::problem_st_hidden)";
    # TODO: take testsets into account
    my $test_count_sql = $is_jury ? '(SELECT COUNT(*) FROM tests T WHERE T.problem_id = P.id) AS test_count,' : '';
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            ${select_code} AS code, P.title AS problem_name, OC.title AS contest_name,
            ($reqs_count_sql $cats::st_accepted$account_condition) AS accepted_count,
            ($reqs_count_sql $cats::st_wrong_answer$account_condition) AS wrong_answer_count,
            ($reqs_count_sql $cats::st_time_limit_exceeded$account_condition) AS time_limit_count,
            P.contest_id - CP.contest_id AS is_linked,
            (SELECT COUNT(*) FROM contest_problems CP1
                WHERE CP1.contest_id <> CP.contest_id AND CP1.problem_id = P.id) AS usage_count,
            OC.id AS original_contest_id, CP.status,
            P.upload_date,
            (SELECT A.login FROM accounts A WHERE A.id = P.last_modified_by) AS last_modified_by,
            SUBSTRING(P.explanation FROM 1 FOR 1) AS has_explanation,
            $test_count_sql CP.testsets, CP.points_testsets
        FROM problems P, contest_problems CP, contests OC
        WHERE CP.problem_id = P.id AND OC.id = P.contest_id AND CP.contest_id = ?$hidden_problems
        ~ . order_by
    );
    if ($contest->is_practice)
    {
        $sth->execute($cid);
    }
    else
    {
        my $aid = $uid || 0; # in a case of anonymous user
        # 'ORDER BY subselect' requires re-specifying the parameter
        $sth->execute($aid, $aid, $aid, $cid); #, (order_by =~ /^ORDER BY\s+(5|6|7)\s+/ ? ($aid) : ()));
    }

    my @status_list;
    if ($is_jury)
    {
        my $n = problem_status_names();
        for (sort keys %$n)
        {
            push @status_list, { id => $_, name => $n->{$_} };
        }
        $t->param(status_list => \@status_list, editable => 1);
    }

    my $text_link_f = $is_jury || $contest->{is_hidden} || $contest->{local_only} ?
        \&url_f : \&CATS::StaticPages::url_static;

    my $fetch_record = sub($)
    {
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
        return (
            href_delete => url_f('problems', 'delete' => $c->{cpid}),
            href_change_status => url_f('problems', 'change_status' => $c->{cpid}),
            href_change_code => url_f('problems', 'change_code' => $c->{cpid}),
            href_replace  => url_f('problems', replace => $c->{cpid}),
            href_download => url_f('problems', download => $c->{pid}),
            href_compare_tests => $is_jury && url_f('compare_tests', pid => $c->{pid}),
            href_problem_history => $is_root && url_f('problem_history', pid => $c->{pid}),
            href_original_contest =>
                url_function('problems', sid => $sid, cid => $c->{original_contest_id}, set_contest => 1),
            href_usage => url_f('contests', has_problem => $c->{pid}),
            show_packages => $show_packages,
            status => $c->{status},
            disabled => !$is_jury && $c->{status} == $cats::problem_st_disabled,
            href_view_problem => $text_link_f->('problem_text', cpid => $c->{cpid}),
            href_explanation => $show_packages && $c->{has_explanation} ?
                url_f('problem_text', cpid => $c->{cpid}, explain => 1) : '',
            problem_id => $c->{pid},
            selected => $c->{pid} == (param('problem_id') || 0),
            code => $c->{code},
            problem_name => $c->{problem_name},
            is_linked => $c->{is_linked},
            usage_count => $c->{usage_count},
            contest_name => $c->{contest_name},
            accept_count => $c->{accepted_count},
            wa_count => $c->{wrong_answer_count},
            tle_count => $c->{time_limit_count},
            upload_date => $c->{upload_date},
            last_modified_by => $c->{last_modified_by},
            testsets => $c->{testsets} || '*',
            points_testsets => $c->{points_testsets},
            test_count => $c->{test_count},
            href_select_testsets => url_f('problem_select_testsets', cpid => $c->{cpid}),
        );
    };

    attach_listview(url_f('problems'), $fetch_record, $sth);

    $sth->finish;

    my $de_list = CATS::DevEnv->new($dbh, active_only => 1);
    my @de = (
        { de_id => 'by_extension', de_name => res_str(536) },
        map {{ de_id => $_->{id}, de_name => $_->{description} }} @{$de_list->{_de_list}} );

    my $pt_url = sub {{ href => $_[0], item => ($_[1] || res_str(538)), target => '_blank' }};
    my $p = $contest->is_practice;
    my @submenu =  grep $_,
        $is_jury ? (
            !$p && $pt_url->(url_f('problem_text', nospell => 1, nokw => 1, notime => 1, noformal => 1)),
            !$p && $pt_url->(url_f('problem_text'), res_str(555)),
            { href => url_f('problems', link => 1), item => res_str(540) },
            { href => url_f('problems', link => 1, move => 1), item => res_str(551) },
            !$p && ({ href => url_f('problems_retest'), item => res_str(556) }),
            { href => url_f('contests', params => $cid), item => res_str(546) },
        )
        : (
            !$p && $pt_url->($text_link_f->('problem_text', cid => $cid)),
        );
    $t->param(
        submenu => \@submenu, title_suffix => res_str(525),
        is_team => $my_is_team, is_practice => $contest->is_practice,
        de_list => \@de, problem_codes => \@cats::problem_codes,
     );
}


sub problem_history_commit_frame
{
    init_template('problem_history_commit.html.tt');
    $t->param(p_diff => escape_html(CATS::Problem::show_commit(@_)));
}


sub problem_history_frame
{
    my $pid = url_param('pid') || 0;
    my $h = url_param('h') || '';
    $is_root && $pid or return redirect url_f('contests');
    return problem_history_commit_frame($pid, $h) if $h;

    init_listview_template('problem_history', 'problem_history', auto_ext('problem_history_full'));
    my @cols = (
        { caption => res_str(1400), order_by => '0', width => '16%' }, # author
        { caption => res_str(634), order_by => '1', width => '9%' }, # author date
        { caption => res_str(1401), order_by => '2', width => '9%' }, # committer date
        { caption => res_str(1402), order_by => '3', width => '4%' }, # commit sha
        { caption => res_str(1403), order_by => '4', width => '40%' } # commit message
    );
    define_columns(url_f('problem_history', pid => $pid), 0, 0, \@cols);

    my $fetch_record = sub {
        my $log = shift @{$_[0]} or return ();
        return (
            %$log,
            href_commit => url_f('problem_history', pid => $pid, h => $log->{sha}),
        );
    };
    attach_listview(url_f('problem_history', pid => $pid), $fetch_record, CATS::Problem::get_log($pid));
}


# Admin adds new user to current contest
sub users_new_save
{
    $is_jury or return;
    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->insert($cid) or return;
}


sub users_edit_frame
{
    init_template('users_edit.html.tt');

    my $id = url_param('edit') or return;
    my $u = CATS::User->new->load($id) or return;
    $t->param(
        %$u, id => $id, countries => \@cats::countries, is_root => $is_root,
        href_action => url_f('users'),
        href_impersonate => url_f('users', impersonate => $id));
}


sub users_edit_save
{
    my $u = CATS::User->new->parse_params;
    # Simple $is_jury check is insufficient since jury member
    # can add any team to his contest.
    my $set_password = param_on('set_password') && $is_root;
    my $id = param('id');

    $u->validate_params(
        validate_password => $set_password, id => $id,
        # Need at least $is_jury in all official contests where $u participated.
        allow_official_rename => $is_root)
        or return;

    $u->{passwd} = $u->{password1} if $set_password;
    delete @$u{qw(password1 password2)};
    $dbh->do(_u $sql->update('accounts', { %$u }, { id => $id }));
    $dbh->commit;
}


sub users_import_frame
{
    init_template('users_import.html.tt');
    $is_root or return;
    $t->param(href_action => url_f('users_import'));
    param('do') or return;
    my $do_import = param('do_import');
    my @report;
    for my $line (split "\r\n", decode_utf8(param('user_list'))) {
        my $u = CATS::User->new;
        @$u{qw(team_name login password1 city)} = split "\t", $line;
        my $r = eval {
            $u->insert($contest->{id}, is_ooc => 0, commit => 0); 'ok'
        } || $@;
        push @report, $u->{team_name} . "-- $r";
    }
    $do_import ? $dbh->commit : $dbh->rollback;
    push @report, ($do_import ? 'Import' : 'Test') . ' complete';
    $t->param(report => join "\n", @report);
}


sub registration_frame
{
    init_template('registration.html.tt');

    $t->param(countries => [ @cats::countries ], href_login => url_f('login'));

    defined param('register')
        or return;

    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->insert(undef, save_settings => 1) or return;
    $t->param(successfully_registred => 1);
}


sub settings_save
{
    my $u = CATS::User->new->parse_params;
    my $set_password = param_on('set_password');

    $u->validate_params(validate_password => $set_password, id => $uid) or return;

    $u->{passwd} = $u->{password1} if $set_password;
    delete @$u{qw(password1 password2)};
    $dbh->do(_u $sql->update('accounts', { %$u }, { id => $uid }));
    $dbh->commit;
}


sub apply_rec
{
    my ($val, $sub) = @_;
    ref $val eq 'HASH' ?
        { map { $_ => apply_rec($val->{$_}, $sub) } keys %$val } :
        $sub->($val);
}


sub settings_frame
{
    init_template('settings.html.tt');
    $settings = {} if defined param('clear') && $is_team;
    settings_save if defined param('edit_save') && $is_team;

    $uid or return;
    my $u = CATS::User->new->load($uid) or return;
    $t->param(
        countries => \@cats::countries, href_action => url_f('users'),
        title_suffix => res_str(518), %$u);
    if ($is_jury) {
        $t->param(langs => [
            map { href => url_f('settings', lang => $_), name => $_ }, @cats::langs
        ]);
    }
    if ($is_root) {
        # Data::Dumper escapes UTF-8 characters into \x{...} sequences.
        # Work around by dumping encoded strings, then decoding the result.
        my $d = Data::Dumper->new([ apply_rec($settings, \&encode_utf8) ]);
        $d->Quotekeys(0);
        $d->Sortkeys(1);
        $t->param(settings => decode_utf8($d->Dump));
    }
}


sub users_send_message
{
    my %p = @_;
    $p{'message'} ne '' or return;
    my $s = $dbh->prepare(qq~
        INSERT INTO messages (id, send_time, text, account_id, received)
            VALUES (?, CURRENT_TIMESTAMP, ?, ?, 0)~
    );
    for (split ':', $p{'user_set'})
    {
        next unless param_on("msg$_");
        $s->bind_param(1, new_id);
        $s->bind_param(2, $p{'message'}, { ora_type => 113 });
        $s->bind_param(3, $_);
        $s->execute;
    }
    $s->finish;
}


sub users_set_tag
{
    my %p = @_;
    ($p{'tag'} || '') ne '' or return;
    my $s = $dbh->prepare(qq~
        UPDATE contest_accounts SET tag = ? WHERE id = ?~);
    for (split ':', $p{user_set})
    {
        param_on("msg$_") or next;
        $s->bind_param(1, $p{tag}, { ora_type => 113 });
        $s->bind_param(2, $_);
        $s->execute;
    }
    $s->finish;
    $dbh->commit;
}


sub users_send_broadcast
{
    my %p = @_;
    $p{'message'} ne '' or return;
    my $s = $dbh->prepare(qq~
        INSERT INTO messages (id, send_time, text, account_id, broadcast)
            VALUES(?, CURRENT_TIMESTAMP, ?, NULL, 1)~
    );
    $s->bind_param(1, new_id);
    $s->bind_param(2, $p{'message'}, { ora_type => 113 });
    $s->execute;
    $s->finish;
}


sub users_delete
{
    my $caid = url_param('delete');
    my ($aid, $srole) = $dbh->selectrow_array(qq~
        SELECT A.id, A.srole FROM accounts A
            INNER JOIN contest_accounts CA ON A.id = CA.account_id
            WHERE CA.id = ?~, {},
        $caid);

    if ($srole)
    {
        $dbh->do(qq~DELETE FROM contest_accounts WHERE id=?~, {}, $caid);
        $dbh->commit;

        unless ($dbh->selectrow_array(qq~
            SELECT COUNT(*) FROM contest_accounts WHERE account_id=?~, {}, $aid))
        {
            $dbh->do(qq~DELETE FROM accounts WHERE id=?~, {}, $aid);
            $dbh->commit;
        }
    }
}


sub users_save_attributes
{
    for (split(':', param('user_set')))
    {
        my $jury = param_on("jury$_");
        my $ooc = param_on("ooc$_");
        my $remote = param_on("remote$_");
        my $hidden = param_on("hidden$_");

        # нельзя снять is_jury у администратора
        my ($srole) = $dbh->selectrow_array(qq~
            SELECT A.srole FROM accounts A
                INNER JOIN contest_accounts CA ON A.id = CA.account_id
                WHERE CA.id = ?~, {},
            $_
        );
        $jury = 1 if !$srole;

        # security: запрещаем менять параметры пользователей в других трнирах
        $dbh->do(qq~
            UPDATE contest_accounts
                SET is_jury = ?, is_hidden = ?, is_remote = ?, is_ooc = ?
                WHERE id = ? AND contest_id = ?~, {},
            $jury, $hidden, $remote, $ooc, $_, $cid
        );
    }
    $dbh->commit;
    CATS::RankTable::remove_cache($cid);
}


sub users_impersonate
{
    my $new_user_id = param('impersonate') or return;
    $dbh->selectrow_array(q~
        SELECT 1 FROM accounts WHERE id = ?~, undef, $new_user_id) or return;
    $dbh->do(q~
        UPDATE accounts SET sid = NULL WHERE id = ?~, undef, $uid);
    $dbh->do(q~
        UPDATE accounts SET last_ip = ?, sid = ? WHERE id = ?~, undef,
        CATS::IP::get_ip(), $sid, $new_user_id);
    $dbh->commit;
    redirect(url_function('contests', sid => $sid));
}


sub users_frame
{
    if ($is_jury)
    {
        users_delete if defined url_param('delete');
        return CATS::User::new_frame if defined url_param('new');
        return users_edit_frame if defined url_param('edit');
    }
    return users_impersonate if defined url_param('impersonate') && $is_root;

    init_listview_template(
        'users' . ($contest->is_practice ? '_practice' : ''),
        'users', auto_ext('users'));

    $t->param(messages => $is_jury, title_suffix => res_str(526));

    if ($is_jury)
    {
        users_new_save if defined param('new_save');
        users_edit_save if defined param('edit_save');

        users_save_attributes if defined param('save_attributes');
        users_set_tag(user_set => param('user_set'), tag => param('tag_to_set'))
            if defined param('set_tag');
        CATS::User::register_by_login(param('login_to_register'), $cid)
            if defined param('register_new');

        if (defined param('send_message'))
        {
            if (param_on('send_message_all'))
            {
                users_send_broadcast(message => param('message_text'));
            }
            else
            {
                users_send_message(user_set => param('user_set'), message => param('message_text'));
            }
            $dbh->commit;
        }
    }

    my @cols;
    if ($is_jury)
    {
        @cols = ( { caption => res_str(616), order_by => 'login', width => '25%' } );
    }

    push @cols,
        { caption => res_str(608), order_by => 'team_name', width => '40%' },
        { caption => res_str(629), order_by => 'tag', width => '5%' };

    if ($is_jury)
    {
        push @cols,
            (
              { caption => res_str(611), order_by => 'is_jury', width => '5%' },
              { caption => res_str(612), order_by => 'is_ooc', width => '5%' },
              { caption => res_str(613), order_by => 'is_remote', width => '5%' },
              { caption => res_str(614), order_by => 'is_hidden', width => '5%' } );
    }

    push @cols, (
        { caption => res_str(607), order_by => 'country', width => '5%' },
        { caption => res_str(609), order_by => 'rating', width => '5%' },
        { caption => res_str(622), order_by => 'is_virtual', width => '5%' } );

    define_columns(url_f('users'), $is_jury ? 3 : 2, 1, \@cols);

    return if !$is_jury && param('json') && $contest->is_practice;

    my $fields =
        'A.id, CA.id, A.country, A.login, A.team_name, A.city, ' .
        'CA.is_jury, CA.is_ooc, CA.is_remote, CA.is_hidden, CA.is_virtual, A.motto, CA.tag';
    my $sql = sprintf qq~
        SELECT $fields, COUNT(DISTINCT R.problem_id) as rating
        FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id
            INNER JOIN contests C ON CA.contest_id = C.id
            LEFT JOIN reqs R ON
                R.state = $cats::st_accepted AND R.account_id = A.id AND R.contest_id = C.id%s
        WHERE C.id = ?%s GROUP BY $fields ~ . order_by,
        ($is_jury ? ('', '') : (
            ' AND (R.submit_time < C.freeze_date OR C.defreeze_date < CURRENT_TIMESTAMP)',
            ' AND CA.is_hidden = 0'));

    my $c = $dbh->prepare($sql);
    $c->execute($cid);

    my $fetch_record = sub($)
    {
        my (
            $aid, $caid, $country_abb, $login, $team_name, $city, $jury,
            $ooc, $remote, $hidden, $virtual, $motto, $tag, $accepted
        ) = $_[0]->fetchrow_array
            or return ();
        my ($country, $flag) = get_flag($country_abb);
        return (
            href_delete => url_f('users', delete => $caid),
            href_edit => url_f('users', edit => $aid),
            href_stats => url_f('user_stats', uid => $aid),
            motto => $motto,
            id => $caid,
            account_id => $aid,
            login => $login,
            editable => $is_jury,
            messages => $is_jury,
            team_name => $team_name,
            city => $city,
            tag => $tag,
            country => $country,
            flag => $flag,
            accepted => $accepted,
            jury => $jury,
            hidden => $hidden,
            ooc => $ooc,
            remote => $remote,
            virtual => $virtual,
         );
    };

    attach_listview(url_f('users'), $fetch_record, $c);

    if ($is_jury)
    {
        $t->param(
            submenu => [
                { href => url_f('users', new => 1), item => res_str(541) },
                { href => url_f('users_import'), item => res_str(564) },
            ],
            editable => 1
        );
    }

    $c->finish;
}


sub user_stats_frame
{
    init_template('user_stats.html.tt');
    my $uid = param('uid') or return;
    my $hidden_cond = $is_root ? '' :
        'AND (CA.is_hidden = 0 OR CA.is_hidden IS NULL) AND C.defreeze_date < CURRENT_TIMESTAMP';
    my $u = $dbh->selectrow_hashref(q~
        SELECT A.*, last_login AS last_login_date
        FROM accounts A WHERE A.id = ?~, { Slice => {} }, $uid) or return;
    my $contests = $dbh->selectall_arrayref(qq~
        SELECT C.id, C.title, CA.id AS caid, CA.is_jury, C.start_date + CA.diff_time AS start_date,
            (SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
                WHERE R.contest_id = C.id AND R.account_id = CA.account_id AND R.state = $cats::st_accepted
            ) AS accepted_count,
            (SELECT COUNT(*) FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.status < $cats::problem_st_hidden
            ) AS problem_count
        FROM contests C INNER JOIN contest_accounts CA ON CA.contest_id = C.id
        WHERE
            CA.account_id = ? AND C.ctype = 0 AND C.is_hidden = 0 $hidden_cond
        ORDER BY C.start_date + CA.diff_time DESC~,
        { Slice => {} }, $uid);
    my $pr = sub { url_f(
        'console', uf => $uid, i_value => -1, se => 'user_stats', show_results => 1, search => $_[0], rows => 30
    ) };
    for (@$contests) {
        $_->{href_send_message} = url_f('send_message_box', caid => $_->{caid}) if $is_root;
        $_->{href_problems} = url_function('problems', sid => $sid, cid => $_->{id});
    }
    $t->param(
        %$u, contests => $contests, is_root => $is_root,
        CATS::IP::linkify_ip(CATS::IP::filter_ip $u->{last_ip}),
        ($is_jury ? (href_edit => url_f('users', edit => $uid)) : ()),
        href_all_problems => $pr->(''),
        href_solved_problems => $pr->('accepted=1'),
        title_suffix => $u->{team_name},
    );
}


sub import_sources_frame
{
    init_listview_template('import_sources', 'import_sources', 'import_sources.html.tt');
    define_columns(url_f('import_sources'), 0, 0, [
        { caption => res_str(625), order_by => '2', width => '30%' },
        { caption => res_str(642), order_by => '3', width => '30%' },
        { caption => res_str(641), order_by => '4', width => '30%' },
        { caption => res_str(643), order_by => '5', width => '10%' },
    ]);

    my $c = $dbh->prepare(qq~
        SELECT ps.id, ps.guid, ps.stype, de.code,
            (SELECT COUNT(*) FROM problem_sources_import psi WHERE ps.guid = psi.guid) AS ref_count,
            ps.fname, ps.problem_id, p.title, p.contest_id
            FROM problem_sources ps INNER JOIN default_de de ON de.id = ps.de_id
            INNER JOIN problems p ON p.id = ps.problem_id
            WHERE ps.guid IS NOT NULL ~.order_by);
    $c->execute;

    my $fetch_record = sub($)
    {
        my $f = $_[0]->fetchrow_hashref or return ();
        return (
            %$f,
            stype_name => $cats::source_module_names{$f->{stype}},
            href_problems => url_function('problems', sid => $sid, cid => $f->{contest_id}),
            href_source => url_f('download_import_source', psid => $f->{id}),
            is_jury => $is_jury,
        );
    };

    attach_listview(url_f('import_sources'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('import_sources') ], is_jury => 1) if $is_jury;
}


sub download_import_source_frame
{
    my $psid = param('psid') or return;
    local $dbh->{ib_enable_utf8} = 0;
    my ($fname, $src) = $dbh->selectrow_array(qq~
        SELECT fname, src FROM problem_sources WHERE id = ? AND guid IS NOT NULL~, undef, $psid) or return;
    binmode(STDOUT, ':raw');
    CATS::Web::content_type('text/plain');
    CATS::Web::headers('Content-Disposition' => "inline;filename=$fname");
    print STDOUT $src;
}


sub prizes_frame
{
    $is_root or return;
    if (my $cgid = url_param('delete')) {
        $dbh->do(qq~DELETE FROM contest_groups WHERE id = ?~, undef, $cgid);
        $dbh->commit;
    }

    defined url_param('edit') and return CATS::Prizes::prizes_edit_frame;
    init_listview_template('prizes', 'prizes', 'prizes.html.tt');

    defined param('edit_save') and CATS::Prizes::prizes_edit_save;

    define_columns(url_f('prizes'), 0, 0, [
        { caption => res_str(601), order_by => '2', width => '30%' },
        { caption => res_str(645), order_by => '3', width => '30%' },
        { caption => res_str(646), order_by => '4', width => '40%' },
    ]);

    my $c = $dbh->prepare(qq~
        SELECT cg.id, cg.name, cg.clist,
            (SELECT LIST(rank || ':' || name, ' ') FROM prizes p WHERE p.cg_id = cg.id) AS prizes
            FROM contest_groups cg ~ . order_by);
    $c->execute;

    my $fetch_record = sub {
        my $f = $_[0]->fetchrow_hashref or return ();
        (
            %$f,
            href_edit=> url_f('prizes', edit => $f->{id}),
            href_delete => url_f('prizes', 'delete' => $f->{id}),
        );
    };

    attach_listview(url_f('prizes'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('prizes') ]);
}


sub rank_table
{
    my $template_name = shift;
    init_template('rank_table_content.html.tt');
    $t->param(printable => url_param('printable'));
    my $rt = CATS::RankTable->new;
    $rt->parse_params;
    $rt->rank_table;
    $contest->{title} = $rt->{title};
    my $s = $t->output;

    init_template($template_name);
    $t->param(rank_table_content => $s, printable => (url_param('printable') || 0));
}


sub rank_table_frame
{
    my $hide_ooc = url_param('hide_ooc') || 0;
    my $hide_virtual = url_param('hide_virtual') || 0;
    my $cache = url_param('cache');
    my $show_points = url_param('points');

    #rank_table('main_rank_table.htm');
    #init_template('main_rank_table_content.htm');
    init_template('rank_table.html.tt');

    my $rt = CATS::RankTable->new;
    $rt->get_contest_list_param;
    $rt->get_contests_info($uid);
    $contest->{title} = $rt->{title};

    my @params = (
        hide_ooc => $hide_ooc, hide_virtual => $hide_virtual, cache => $cache,
        clist => $rt->{contest_list}, points => $show_points,
        filter => Encode::decode_utf8(url_param('filter') || undef),
        show_prizes => (url_param('show_prizes') || 0),
    );
    $t->param(href_rank_table_content => url_f('rank_table_content', @params));
    my $submenu =
        [ { href => url_f('rank_table_content', @params, printable => 1), item => res_str(538) } ];
    if ($is_jury)
    {
        push @$submenu,
            { href => url_f('rank_table', @params, cache => 1 - ($cache || 0)), item => res_str(553) },
            { href => url_f('rank_table', @params, points => 1 - ($show_points || 0)), item => res_str(554) };
    }
    $t->param(submenu => $submenu, title_suffix => res_str(529));
}


sub rank_table_content_frame
{
    rank_table('rank_table_iframe.html.tt');
}


sub rank_problem_details
{
    init_template('main_rank_problem_details.htm');
    $is_jury or return;

    my ($pid) = url_param('pid') or return;

    my $runs = $dbh->selectall_arrayref(q~
        SELECT
            R.id, R.state, R.account_id, R.points
        FROM reqs R WHERE R.contest_id = ? AND R.problem_id = ?
        ORDER BY R.id~, { Slice => {} },
        $cid, $pid);

    for (@$runs)
    {
        1;
    }
}


sub about_frame
{
    init_template('about.html.tt');
    my $problem_count = $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM problems P INNER JOIN contests C ON C.id = P.contest_id
            WHERE C.is_hidden = 0 OR C.is_hidden IS NULL~);
    $t->param(problem_count => $problem_count);
}


sub generate_menu
{
    my $logged_on = $sid ne '';

    my @left_menu = (
        { item => $logged_on ? res_str(503) : res_str(500),
          href => $logged_on ? url_function('logout', sid => $sid) : url_function('login') },
        { item => res_str(502), href => url_f('contests') },
        { item => res_str(525), href => url_f('problems') },
        ($is_jury || !$contest->is_practice ? { item => res_str(526), href => url_f('users') } : ()),
        { item => res_str(510),
          href => url_f('console', $is_jury ? () : (uf => $uid || get_anonymous_uid())) },
        ($is_jury ? () : { item => res_str(557), href => url_f('import_sources') }),
    );

    if ($is_jury)
    {
        push @left_menu, (
            { item => res_str(548), href => url_f('compilers') },
            { item => res_str(545), href => url_f('similarity') }
        );
    }
    else
    {
        push @left_menu, (
            { item => res_str(517), href => url_f('compilers') },
            { item => res_str(549), href => url_f('keywords') } );
    }

    unless ($contest->is_practice)
    {
        push @left_menu, ({
            item => res_str(529),
            href => url_f('rank_table', $is_jury ? () : (cache => 1, hide_virtual => !$is_virtual))
        });
    }

    my @right_menu = ();

    if ($uid && (url_param('f') ne 'logout'))
    {
        @right_menu = ( { item => res_str(518), href => url_f('settings') } );
    }

    push @right_menu, (
        { item => res_str(544), href => url_f('about') },
        { item => res_str(501), href => url_f('registration') } );

    attach_menu('left_menu', undef, \@left_menu);
    attach_menu('right_menu', 'about', \@right_menu);
}


sub interface_functions ()
{
    {
        login => \&login_frame,
        logout => \&logout_frame,
        registration => \&registration_frame,
        settings => \&settings_frame,
        contests => \&contests_frame,
        console_content => \&CATS::Console::content_frame,
        console => \&CATS::Console::console_frame,
        console_export => \&CATS::Console::export,
        console_graphs => \&CATS::Console::graphs,
        problems => \&problems_frame,
        problems_retest => \&problems_retest_frame,
        problem_select_testsets => \&problem_select_testsets,
        problem_history => \&problem_history_frame,
        users => \&users_frame,
        users_import => \&users_import_frame,
        user_stats => \&user_stats_frame,
        compilers => \&CATS::Compilers::compilers_frame,
        judges => \&CATS::Judges::judges_frame,
        keywords => \&CATS::Keywords::keywords_frame,
        import_sources => \&import_sources_frame,
        prizes => \&prizes_frame,
        download_import_source => \&download_import_source_frame,

        answer_box => \&CATS::Messages::answer_box_frame,
        send_message_box => \&CATS::Messages::send_message_box_frame,

        run_log => \&CATS::RunDetails::run_log_frame,
        view_source => \&CATS::RunDetails::view_source_frame,
        download_source => \&CATS::RunDetails::download_source_frame,
        run_details => \&CATS::RunDetails::run_details_frame,
        diff_runs => \&CATS::RunDetails::diff_runs_frame,

        test_diff => \&CATS::Stats::test_diff_frame,
        compare_tests => \&CATS::Stats::compare_tests_frame,
        rank_table_content => \&rank_table_content_frame,
        rank_table => \&rank_table_frame,
        rank_problem_details => \&rank_problem_details,
        problem_text => \&problem_text_frame,
        envelope => \&CATS::Messages::envelope_frame,
        about => \&about_frame,
        static => \&static_frame,

        similarity => \&CATS::Stats::similarity_frame,
        personal_official_results => \&CATS::Contest::personal_official_results,
    }
}


sub accept_request
{
    my $output_file = '';
    if (CATS::StaticPages::is_static_page)
    {
        $output_file = CATS::StaticPages::process_static()
            or return;
    }
    initialize;
    $CATS::Misc::init_time = Time::HiRes::tv_interval(
        $CATS::Misc::request_start_time, [ Time::HiRes::gettimeofday ]);

    unless (defined $t)
    {
        my $function_name = url_param('f') || '';
        my $fn = interface_functions()->{$function_name} || \&about_frame;
        # Function returns -1 if there is no need to generate output, e.g. a redirect was issued.
        ($fn->() || 0) == -1 and return;
    }
    save_settings;

    generate_menu if defined $t;
    generate_output($output_file);
}


sub handler {
    my $r = shift;

    init_request($r);
    $CATS::Misc::request_start_time = [ Time::HiRes::gettimeofday ];
    CATS::DB::sql_connect;
    $dbh->rollback; # In a case of abandoned transaction

    accept_request();
    $dbh->rollback;

    return get_return_code();
}


1;
