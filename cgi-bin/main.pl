#!/usr/bin/perl
use strict;
use warnings;
no warnings 'redefine';
use encoding 'utf8', STDIN => undef;

use File::Temp qw/tempfile tmpnam mktemp/;
use Encode;
#use CGI::Fast qw(:standard);
use CGI qw(:standard);
use CGI::Util qw(unescape escape);
#use FCGI;


use Algorithm::Diff;
use Text::Aspell;
use Data::Dumper;
use Storable ();
use Time::HiRes;
use List::Util qw(max);

my $cats_lib_dir;
BEGIN {
    $cats_lib_dir = $ENV{CATS_DIR};
    $cats_lib_dir =~ s/\/$//;
}
use lib $cats_lib_dir;


use CATS::DB;
use CATS::Constants;
use CATS::BinaryFile;
use CATS::DevEnv;
use CATS::Misc qw(:all);
use CATS::Data qw(:all);
use CATS::IP;
use CATS::Problem;
use CATS::RankTable;
use CATS::Diff;
use CATS::StaticPages;
use CATS::TeX::Lite;
use CATS::Testset;

use vars qw($html_code $current_pid $spellchecker $text_span);


sub login_frame
{
    init_template('main_login.htm');

    my $login = param('login') or return;
    $t->param(login => $login); 
    my $cid = param('contest');
    my $passwd = param('passwd');

    my ($aid, $passwd3, $locked) = $dbh->selectrow_array(qq~
        SELECT id, passwd, locked FROM accounts WHERE login=?~, {}, $login);

    $aid or return msg(39);

    $passwd3 eq $passwd or return msg(40);

    !$locked or msg(41);

    my $ok = 0;
    my @ch = ('A'..'Z', 'a'..'z', '0'..'9');
    for (1..20)
    {
        $sid = join '', map { $ch[rand @ch] } 1..30;
        
        my $last_ip = CATS::IP::get_ip();
        
        if ($dbh->do(qq~
            UPDATE accounts SET sid = ?, last_login = CATS_SYSDATE(), last_ip = ?
                WHERE id = ?~,
            {}, $sid, $last_ip, $aid
        ))
        {
            $dbh->commit;

            my $cid = $dbh->selectrow_array(qq~SELECT id FROM contests WHERE ctype = 1~);

            $t = undef;
            print redirect(-uri => url_function('contests', sid => $sid, cid => $cid));
            return;
        }
    }
    die 'Can not generate sid';
}


sub logout_frame
{
    init_template('main_logout.htm');

    $cid = '';
    $sid = '';
    $t->param(href_login => url_f('login'));

    $dbh->do(qq~UPDATE accounts SET sid = NULL WHERE id = ?~, {}, $uid);
    $dbh->commit;
}


sub contests_new_frame
{
    init_template('main_contests_new.htm');

    my $date = $dbh->selectrow_array(qq~SELECT CATS_DATE(CATS_SYSDATE()) FROM accounts~);
    $date =~ s/\s*$//;
    $t->param(
        start_date => $date, freeze_date => $date,
        finish_date => $date, open_date => $date,
        can_edit => 1,
        href_action => url_f('contests')
    );
}


sub contest_checkbox_params()
{qw(
    free_registration run_all_tests
    show_all_tests show_test_resources show_checker_comment
    is_official show_packages local_only is_hidden
)}


sub contest_string_params()
{qw(
    contest_name start_date freeze_date finish_date open_date rules
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
    $p{$_} ||= 0 for (qw(is_jury is_pop is_hidden is_virtual));
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
            id, title, start_date, freeze_date, finish_date, defreeze_date, rules,
            ctype,
            closed, run_all_tests, show_all_tests,
            show_test_resources, show_checker_comment, is_official, show_packages, local_only,
            is_hidden
        ) VALUES(
            ?, ?, CATS_TO_DATE(?), CATS_TO_DATE(?), CATS_TO_DATE(?), CATS_TO_DATE(?), ?,
            0,
            ?, ?, ?, ?, ?, ?, ?, ?, ?)~,
        {},
        $cid, @$p{contest_string_params()},
        @$p{contest_checkbox_params()}
    );

    # автоматически зарегистрировать всех администраторов как жюри
    my $root_accounts = $dbh->selectcol_arrayref(qq~
        SELECT id FROM accounts WHERE srole = ?~, undef, $cats::srole_root);
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

    init_template('main_contest_params.htm');  

    my $p = $dbh->selectrow_hashref(qq~
        SELECT
            title AS contest_name,
            CATS_DATE(start_date) AS start_date,
            CATS_DATE(freeze_date) AS freeze_date,
            CATS_DATE(finish_date) AS finish_date,
            CATS_DATE(defreeze_date) AS open_date,
            1 - closed AS free_registration,
            run_all_tests, show_all_tests, show_test_resources, show_checker_comment,
            is_official, show_packages, local_only, rules, is_hidden
        FROM contests WHERE id = ?~, { Slice => {} },
        $id
    );
    # наверное, на самом деле надо исправить CATS_DATE
    for (qw(start_date freeze_date finish_date open_date)) {
        $p->{$_} =~ s/\s*$//;
    }
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
            title=?, start_date=CATS_TO_DATE(?), freeze_date=CATS_TO_DATE(?), 
            finish_date=CATS_TO_DATE(?), defreeze_date=CATS_TO_DATE(?), rules=?,
            closed=?, run_all_tests=?, show_all_tests=?,
            show_test_resources=?, show_checker_comment=?, is_official=?, show_packages=?,
            local_only=?, is_hidden=?
        WHERE id=?~,
        {},
        @$p{contest_string_params()},
        @$p{contest_checkbox_params()},
        $edit_cid
    );
    $dbh->commit;
    # если переименовали текущий турнир, сразу изменить заголовок окна
    if ($edit_cid == $cid)
    {
        $contest->{title} = $p->{contest_name};
    }
}


sub contest_online_registration
{
    !get_registered_contestant(contest_id => $cid)
        or return msg(111);

    $contest->{time_since_finish} <= 0
        or return msg(108);

    !$contest->{closed}
        or return msg(105);

    register_contest_account(contest_id => $cid, account_id => $uid, diff_time => 0);
    $dbh->commit;
}


sub contest_virtual_registration
{
    my ($registered, $is_virtual) = get_registered_contestant(
         fields => '1, is_virtual', contest_id => $cid);
        
    !$registered || $is_virtual
        or return msg(114);

    $contest->{time_since_start} >= 0
        or return msg(109);
    
    # В официальных турнирах виртуальное участие резрешено тоьлко после окончания.
    $contest->{time_since_finish} >= 0 || !$contest->{is_official}
        or return msg(122);

    !$contest->{closed}
        or return msg(105);

    # при повторной регистрации удаляем старые результаты
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
        is_virtual => 1, diff_time => $contest->{time_since_start});
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


sub common_contests_view ($)
{
    my ($c) = @_;
    return (
       id => $c->{id},
       contest_name => $c->{title}, 
       start_date => $c->{start_date}, 
       finish_date => $c->{finish_date},
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
    # HACK: начальная страница -- список турниров, выводится очень часто
    # при отсутствии поиска выбираем только первую страницу + 1 запись.
    (($page || 0) == 0 && !$search ? 'FIRST ' . ($visible + 1) : '') .
    qq~c.ctype, c.id, c.title, c.start_date AS sd, c.finish_date AS fd,
    CATS_DATE(c.start_date) AS start_date, CATS_DATE(c.finish_date) AS finish_date,
    c.closed, c.is_official, c.rules~
}


sub authenticated_contests_view ()
{
    my $cf = contest_fields();
    #my $not_hidden = 'c.is_hidden = 0 OR c.is_hidden IS NULL';
    my $sth = $dbh->prepare(qq~
        SELECT
            $cf, CA.is_virtual, CA.is_jury, CA.id AS registered
        FROM contests C LEFT JOIN
            contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        WHERE
            CA.account_id IS NOT NULL OR COALESCE(C.is_hidden, 0) = 0 ~ . order_by);
    $sth->execute($uid);

    my $fetch_contest = sub($) 
    {
        my $c = $_[0]->fetchrow_hashref or return;
        return (
            common_contests_view($c),
            authorized => 1,
            editable => $c->{is_jury},
            deletable => $is_root,
            registered_online => $c->{registered} && !$c->{is_virtual},
            registered_virtual => $c->{registered} && $c->{is_virtual}, 
            href_delete => url_f('contests', delete => $c->{id}),
        );
    };
    return ($fetch_contest, $sth);
}


sub anonymous_contests_view ()
{
    my $cf = contest_fields();
    my $sth = $dbh->prepare(qq~
        SELECT $cf FROM contests C WHERE COALESCE(C.is_hidden, 0) = 0 ~ . order_by
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
        print redirect(-uri => url_f('rank_table', clist => join ',', @clist));
        return;
    }

    if (defined url_param('new') && $is_root)
    {
        contests_new_frame;
        return;
    }

    try_contest_params_frame and return;

    init_listview_template('contests_' . ($uid || ''), 'contests', 'main_contests.htm');

    if (defined url_param('delete') && $is_root)   
    {    
        my $cid = url_param('delete');
        $dbh->do(qq~DELETE FROM contests WHERE id = ?~, {}, $cid);
        $dbh->commit;
    }

    if (defined param('new_save') && $is_root)
    {
        contests_new_save;
    }

    if (defined param('edit_save') &&
        get_registered_contestant(fields => 'is_jury', contest_id => param('id')))
    {
        contests_edit_save;
    }

    if (defined param('online_registration'))
    {
        contest_online_registration;
    }

    my $vr = param('virtual_registration');
    if (defined $vr && $vr)
    {
        contest_virtual_registration;
    }
    
    if (defined url_param('set_contest'))
    {
        contests_select_current;
    }

    define_columns(url_f('contests'), 1, 1, [
        { caption => res_str(601), order_by => '1 DESC, 2', width => '40%' },
        { caption => res_str(600), order_by => '1 DESC, 4', width => '20%' },
        { caption => res_str(631), order_by => '1 DESC, 5', width => '20%' },
        { caption => res_str(630), order_by => '1 DESC, 8', width => '20%' } ]);

    attach_listview(url_f('contests'),
        defined $uid ? authenticated_contests_view : anonymous_contests_view);

    if ($is_root)
    {
        my $submenu = [ { href_item => url_f('contests', new => 1), item_name => res_str(537) } ];
        $t->param(submenu => $submenu);
    }

    $t->param(
        authorized => defined $uid,
        href_contests => url_f('contests'),
        editable => $is_root,
        is_registered => defined $uid && get_registered_contestant(contest_id => $cid) || 0,
    );
}

sub init_console_listview_additionals
{
    $additional ||= '1_hours';
    my $v = param('history_interval_value');
    my $u = param('history_interval_units');
    if (!defined $v || !defined $u)
    {
        ($v, $u) = ( $additional =~ /^(\d+)_(\w+)$/ );
        $v = 1 if !defined $v;
        $u = 'hours' if !defined $u; 
    }
    $additional = "${v}_$u";
    return ($v, $u);
}


sub russian ($)
{
    Encode::decode('KOI8-R', $_[0]);
}


sub get_anonymous_uid
{
    scalar $dbh->selectrow_array(qq~
        SELECT id FROM accounts WHERE login = ?~, undef, $cats::anonymous_login);
}


sub console_read_time_interval
{
    my ($v, $u) = init_console_listview_additionals;
    my @text = split /\|/, res_str(121);
    my $units = [
        { value => 'hours', k => 0.04167 },
        { value => 'days', k => 1 },
        { value => 'months', k => 30 },
    ];
    map { $units->[$_]->{text} = $text[$_] } 0..$#$units;
    
    my $selected_unit = $units->[0];
    for (@$units)
    {
        if ($_->{value} eq $u)
        {
            $selected_unit = $_;
            last;
        }
    }
    $selected_unit->{selected} = 1;

    $t->param(
        'history_interval_value' => [
            map { {value => $_, text => $_ || russian('all'), selected => $v eq $_} } (1..5, 10, 0)
        ],
        'history_interval_units' => $units
    );

    return $v > 0 ? $v * $selected_unit->{k} : 100000;
}


sub console
{
    my $template_name = shift;
    init_listview_template("console$cid" . ($uid || ''), 'console', 'main_console_content.htm');

    my $day_count = console_read_time_interval;
    my %console_select = (
        run => q~
            1 AS rtype,
            R.submit_time AS rank,
            CATS_DATE(R.submit_time) AS submit_time,
            R.id AS id,
            R.state AS request_state,
            R.failed_test AS failed_test,
            P.title AS problem_title,
            CAST(NULL AS INTEGER) AS clarified,
            D.t_blob AS question,
            D.t_blob AS answer,
            D.t_blob AS jury_message,
            A.id AS team_id,
            A.team_name AS team_name,
            A.country AS country,
            A.last_ip AS last_ip,
            CA.id,
            CA.contest_id~,
        question => q~
            2 AS rtype,
            Q.submit_time AS rank,
            CATS_DATE(Q.submit_time) AS submit_time,
            Q.id AS id,
            CAST(NULL AS INTEGER) AS request_state,
            CAST(NULL AS INTEGER) AS failed_test,
            CAST(NULL AS VARCHAR(200)) AS problem_title,
            Q.clarified AS clarified,
            Q.question AS question,
            Q.answer AS answer,
            D.t_blob AS jury_message,
            A.id AS team_id,
            A.team_name AS team_name,
            A.country AS country,
            A.last_ip AS last_ip,
            CA.id,
            CA.contest_id~,
        message => q~
            3 AS rtype,
            M.send_time AS rank,
            CATS_DATE(M.send_time) AS submit_time,
            M.id AS id,
            CAST(NULL AS INTEGER) AS request_state,
            CAST(NULL AS INTEGER) AS failed_test,
            CAST(NULL AS VARCHAR(200)) AS problem_title,
            CAST(NULL AS INTEGER) AS clarified,
            D.t_blob AS question,
            D.t_blob AS answer,
            M.text AS jury_message,
            A.id AS team_id,
            A.team_name AS team_name,
            A.country AS country,
            A.last_ip AS last_ip,
            CA.id,
            CA.contest_id
        ~,
        broadcast => q~
            4 AS rtype,
            M.send_time AS rank,
            CATS_DATE(M.send_time) AS submit_time,
            M.id AS id,
            CAST(NULL AS INTEGER) AS request_state,
            CAST(NULL AS INTEGER) AS failed_test,
            CAST(NULL AS VARCHAR(200)) AS problem_title,
            CAST(NULL AS INTEGER) AS clarified,
            D.t_blob AS question,
            D.t_blob AS answer,
            M.text AS jury_message,
            CAST(NULL AS INTEGER) AS team_id,
            CAST(NULL AS VARCHAR(200)) AS team_name,
            CAST(NULL AS VARCHAR(30)) AS country,
            CAST(NULL AS VARCHAR(100)) AS last_ip,
            CAST(NULL AS INTEGER),
            CAST(NULL AS INTEGER)
            FROM messages M, dummy_table D
        ~,
    );

    my $user_filter = sprintf '%d', url_param('uf') || 0;

    my $events_filter = $user_filter ? 'AND A.id = ?' : '';
    my @events_filter_params = $user_filter ? ($user_filter) : ();

    my $c;
    if ($is_jury)
    {
        my $runs_filter = $is_root ? '' : ' C.id = ? AND';
        my $msg_filter = $is_root ? '' : ' AND CA.contest_id = ?';
        my @cid = $is_root ? () : ($cid);
        $c = $dbh->prepare(qq~
            SELECT
                $console_select{run}
                FROM reqs R, problems P, accounts A, contests C, contest_accounts CA, dummy_table D 
                WHERE (R.submit_time > CATS_SYSDATE() - $day_count) AND R.contest_id=C.id AND$runs_filter
                R.problem_id=P.id AND R.account_id=A.id AND CA.account_id=A.id AND CA.contest_id=R.contest_id
                $events_filter
            UNION
            SELECT
                $console_select{question}
                FROM questions Q, contest_accounts CA, dummy_table D, accounts A
                WHERE (Q.submit_time > CATS_SYSDATE() - $day_count) AND
                Q.account_id=CA.id AND A.id=CA.account_id$msg_filter
                $events_filter
            UNION
            SELECT
                $console_select{message}
                FROM messages M, contest_accounts CA, dummy_table D, accounts A
                WHERE (M.send_time > CATS_SYSDATE() - $day_count) AND
                M.account_id = CA.id AND A.id = CA.account_id$msg_filter
                $events_filter
	        UNION
            SELECT
                $console_select{broadcast}
                WHERE (M.send_time > CATS_SYSDATE() - $day_count) AND M.broadcast=1
            ORDER BY 2 DESC~);
        $c->execute(
            @cid, @events_filter_params,
            @cid, @events_filter_params,
            @cid, @events_filter_params);
    }
    elsif ($is_team)
    {
        $c = $dbh->prepare(qq~
            SELECT
                $console_select{run}
                FROM
                    reqs R
                    INNER JOIN problems P ON R.problem_id = P.id
                    INNER JOIN accounts A ON R.account_id = A.id
                    INNER JOIN contests C ON C.id = R.contest_id
                    INNER JOIN contest_accounts CA ON C.id = CA.contest_id AND CA.account_id = A.id
                    , dummy_table D
                WHERE (R.submit_time > CATS_SYSDATE() - $day_count) AND
                    C.id=? AND CA.is_hidden=0 AND
                    (A.id=? OR R.submit_time < C.freeze_date OR CATS_SYSDATE() > C.defreeze_date)
                $events_filter
            UNION
            SELECT
                $console_select{question}
                FROM questions Q, contest_accounts CA, dummy_table D, accounts A
                WHERE (Q.submit_time > CATS_SYSDATE() - $day_count) AND
                Q.account_id=CA.id AND CA.contest_id=? AND CA.account_id=A.id AND A.id=?
            UNION
            SELECT
                $console_select{message}
                FROM messages M, contest_accounts CA, dummy_table D, accounts A 
                WHERE (M.send_time > CATS_SYSDATE() - $day_count) AND
                    M.account_id=CA.id AND CA.contest_id=? AND CA.account_id=A.id AND A.id=?
	        UNION
            SELECT
                $console_select{broadcast}
                WHERE (M.send_time > CATS_SYSDATE() - $day_count) AND M.broadcast=1
            ORDER BY 2 DESC~);
        $c->execute(
            $cid, $uid, @events_filter_params,
            $cid, $uid,
            $cid, $uid,
        );
    }
    else
    {
        $c = $dbh->prepare(qq~
            SELECT
                $console_select{run}
                FROM reqs R, problems P, accounts A, dummy_table D, contests C, contest_accounts CA
                WHERE (R.submit_time > CATS_SYSDATE() - $day_count) AND
                    R.problem_id=P.id AND R.contest_id=? AND R.account_id=A.id AND C.id=R.contest_id AND
                    CA.account_id=A.id AND CA.contest_id=C.id AND CA.is_hidden=0 AND 
                    (R.submit_time < C.freeze_date OR CATS_SYSDATE() > C.defreeze_date)
                    $events_filter
            UNION
            SELECT
                $console_select{broadcast}
                WHERE (M.send_time > CATS_SYSDATE() - $day_count) AND M.broadcast=1
            ORDER BY 2 DESC~);
        $c->execute($cid, @events_filter_params);
    }

    my $fetch_console_record = sub($)
    {            
        my ($rtype, $rank, $submit_time, $id, $request_state, $failed_test, 
            $problem_title, $clarified, $question, $answer, $jury_message,
            $team_id, $team_name, $country_abb, $last_ip, $caid, $contest_id
        ) = $_[0]->fetchrow_array
            or return ();

        $request_state = -1 unless defined $request_state;
  
        my ($country, $flag) = get_flag($country_abb);
        my $last_ip_short = '';
        $last_ip ||= '';
        for ($last_ip)
        {
            $_ = CATS::IP::filter_ip($_);
            m/(^\S+)/;
            $last_ip_short = $1 || '';
            $_ = '' if $last_ip_short eq $_;
        }
        return (
            country => $country,
            flag => $flag, 
            is_submit_result =>     $rtype == 1,
            is_question =>          $rtype == 2,
            is_message =>           $rtype == 3,
            is_broadcast =>         $rtype == 4,
            clarified =>            $clarified,
            href_details => (
                ($uid && $team_id && $uid == $team_id) ? url_f('run_details', rid => $id) : ''
            ),
            href_delete =>          $is_root ? url_f('console', delete_question => $id) : undef,
            href_answer_box =>      $is_jury ? url_f('answer_box', qid => $id) : undef,
            href_send_message_box =>$is_jury ? url_f('send_message_box', caid => $caid) : undef,
            'time' =>               $submit_time,
            problem_title =>        $problem_title,
            state_to_display($request_state),
            failed_test_index =>    $failed_test,
            question_text =>        $question,
            answer_text =>          $answer,
            message_text =>         $jury_message,
            team_name =>            $team_name,
            last_ip =>              $last_ip,
            last_ip_short =>        $last_ip_short,
            is_jury =>              $is_jury,
            id      =>              $id,
            contest_id =>           $contest_id,
        );
    };
            
    attach_listview(
        url_f('console'), $fetch_console_record, $c, undef, { page_params => { uf => $user_filter } });

    $c->finish;

    if ($is_team)
    {
        my @envelopes;
        my $c = $dbh->prepare(qq~
            SELECT id FROM reqs
              WHERE account_id=? AND state>=$cats::request_processed AND received=0 AND contest_id=?~
        );
        $c->execute($uid, $cid);
        while (my ($id) = $c->fetchrow_array)
        {
            push @envelopes, { href_envelope => url_f('envelope', rid => $id) };
        }

        $t->param(envelopes => [ @envelopes ]);

        $dbh->do(qq~
            UPDATE reqs SET received=1
                WHERE account_id=? AND state>=$cats::request_processed
                AND received=0 AND contest_id=?~, {},
            $uid, $cid);
        $dbh->commit;
    }

    $t->param(
        href_my_events_only => url_f('console', uf => ($uid || get_anonymous_uid())),
        href_all_events => url_f('console', uf => 0),
        user_filter => $user_filter
    );
    my $s = $t->output;
    init_template($template_name);

    $t->param(console_content => $s, is_team => $is_team);
}


sub send_question_to_jury
{
    my ($question_text) = @_;

    $is_team && defined $question_text && $question_text ne ''
        or return;

    my $cuid = get_registered_contestant(fields => 'id', contest_id => $cid);

    my ($previous_question_text) = $dbh->selectrow_array(qq~
        SELECT question FROM questions WHERE account_id = ? ORDER BY submit_time DESC~, {},
        $cuid
    );
    ($previous_question_text || '') ne $question_text or return;
    
    my $s = $dbh->prepare(qq~
        INSERT INTO questions(id, account_id, submit_time, question, received, clarified)
        VALUES (?, ?, CATS_SYSDATE(), ?, 0, 0)~
    );
    $s->bind_param(1, new_id);
    $s->bind_param(2, $cuid);       
    $s->bind_param(3, $question_text, { ora_type => 113 } );
    $s->execute;
    $s->finish;
    $dbh->commit;
    1;
}


sub retest_submissions
{
    my ($selection) = @_;
    my $count = 0;
    my @sanitized_runs = grep $_ ne '', split /\D+/, $selection;
    for (@sanitized_runs)
    {
        enforce_request_state(request_id => $_, state => $cats::st_not_processed)
            and ++$count;
    }
    return $count;
}


sub delete_question
{
    my ($qid) = @_;
    $is_root or return;
    $dbh->do(qq~DELETE FROM questions WHERE id = ?~, undef, $qid);
    $dbh->commit;
}


sub console_frame
{        
    init_listview_template("console$cid" . ($uid || ''), 'console', 'main_console.htm');  
    my ($v, $u) = init_console_listview_additionals;
    
    my $question_text = param('question_text');
    my $selection = param('selection');
   
    if (my $qid = param('delete_question'))
    {
        delete_question($qid);
    }
    
    if (defined param('retest'))
    {
        if (retest_submissions($selection))
        {
            $selection = '';
        }
    }

    if (defined param('send_question'))
    {
        send_question_to_jury($question_text)
            and $question_text = '';
    }

    my $p = sub { param($_[0]) ? ($_[0] => param($_[0])) : () };
    
    $t->param(
        href_console_content => url_f('console_content',
            uf => url_param('uf') || '', page => (url_param('page') || 0),
            # Эти параметры обычно сохраняются в cookie,
            # но из-за асинхронности обновления iframe может оказаться,
            # что после выбора новых значений используются всё-таки старые.
            # Поэтому передаём параметры непосредственно в URL.
            map { (param($_) ? ($_ => param($_)) : ()) }
                qw(history_interval_value history_interval_units display_rows search)
        ),
        is_team => $is_team,
        is_jury => $is_jury,
        question_text => $question_text,
        selection => $selection,
        href_view_source => url_f('view_source'),
        href_run_details => url_f('run_details'),
        href_run_log => url_f('run_log'),
        href_diff => url_f('diff_runs'),
    );
}


sub console_content_frame
{
    console('main_console_iframe.htm');  
}


sub problems_change_status ()
{
    my $cpid = param('change_status')
      or return msg(54);
    
    my $new_status = param('status');
    exists problem_status_names()->{$new_status} or return;
    
    $dbh->do(qq~
        UPDATE contest_problems SET status = ?
            WHERE contest_id = ? AND id = ?~, {},
        $new_status, $cid, $cpid);
    $dbh->commit;
    # Возможно изменение статуса hidden
    CATS::StaticPages::invalidate_problem_text(cid => $cid);
}


sub show_unused_problem_codes ()
{
    my $c = $dbh->selectcol_arrayref(qq~
        SELECT code FROM contest_problems WHERE contest_id = ?~, {},
        $cid
    );
    my %used_codes;
    $used_codes{$_ || ''} = undef for @$c;
    
    my @unused_codes = grep !exists($used_codes{$_}), 'A'..'Z';
    
    $t->param(
        code_array => [ map({ code => $_ }, @unused_codes) ],
        too_many_problems => !@unused_codes,
    );
}


sub problems_new_frame
{
    init_template('main_problems_new.htm');

    show_unused_problem_codes;
    $t->param(href_action => url_f('problems'));
}


sub add_problem_to_contest
{
    my ($pid, $problem_code) = @_;
    CATS::StaticPages::invalidate_problem_text(cid => $cid);
    return $dbh->do(qq~
        INSERT INTO contest_problems(id, contest_id, problem_id, code, status)
            VALUES (?,?,?,?,?)~, {},
        new_id, $cid, $pid, $problem_code,
        # Если не-архивный турнир уже идёт, добавляемые задачи сразу получают статус hidden
        $contest->{time_since_start} > 0 && $contest->{ctype} == 0 ?
            $cats::problem_st_hidden : $cats::problem_st_ready);
}


sub save_uploaded_file
{
    my ($file) = @_;
    my ($fh, $fname) = tmpnam;
    my ($br, $buffer);
    #$file->open(':raw');
    #binmode $fh, ':raw'; binmode $file, ':raw'; warn $file;
    while ($br = sysread($file, $buffer, 16384))
    {
        syswrite($fh, $buffer, $br);
    }
    close $fh;
    return $fname;
}


sub check_problem_code
{
    my ($problem_code) = @_;
    if ($contest->is_practice)
    {
        undef $$problem_code;
        return 1;
    }
    $$problem_code =~ /^[A-Z0-9]$/ or return msg(134);

    my ($prev) = $dbh->selectrow_array(q~
        SELECT id FROM contest_problems WHERE contest_id = ? AND code = ?~, {},
        $cid, $$problem_code);
    return $prev ? msg(133) : 1;
}


sub problems_new_save
{
    my $file = param('zip') || '';
    $file =~ /\.(zip|ZIP)$/
        or return msg(53);
    my $fname = save_uploaded_file($file);
    my $problem_code = param('problem_code');
    check_problem_code(\$problem_code) or return;

    my CATS::Problem $p = CATS::Problem->new;
    my $error = $p->load($fname, $cid, new_id, 0);
    $t->param(problem_import_log => $p->encoded_import_log());
    $error ||= !add_problem_to_contest($p->{id}, $problem_code);

    $error ? $dbh->rollback : $dbh->commit;
    msg(52) if $error;
    unlink $fname;
}


sub problems_link_save
{       
    my $pid = param('problem_id')
        or return msg(104);

    my $problem_code = param('problem_code');
    check_problem_code(\$problem_code) or return;
    my $move_problem = param('move');
    if ($move_problem)
    {
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
    add_problem_to_contest($pid, $problem_code);
    if ($move_problem)
    {
        $dbh->do(q~
            UPDATE problems SET contest_id = ? WHERE id = ?~, undef, $cid, $pid);
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
     
    # Запрет на замену прилинкованных задач. По-первых, для надёжности,
    # а во-вторых, это секурити -- чтобы не проверять is_jury($contest_id).
    $contest_id == $cid
        or return msg(117);
    my $fname = save_uploaded_file($file);

    my CATS::Problem $p = CATS::Problem->new;
    $p->{old_title} = $old_title unless param('allow_rename');
    my $error = $p->load($fname, $cid, $pid, 1);
    $t->param(problem_import_log => $p->encoded_import_log());

    $error ? $dbh->rollback : $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(pid => $pid);
    msg(52) if $error;
    #unlink $fname;
}


sub problems_all_frame
{
    init_listview_template('link_problem_' || ($uid || ''),
        'link_problem', 'main_problems_link.htm');

    my $link = url_param('link');
    my $kw = url_param('kw');

    $link and show_unused_problem_codes;

    my $cols = [
        { caption => res_str(602), order_by => '2', width => '30%' }, 
        { caption => res_str(603), order_by => '3', width => '30%' },                    
        { caption => res_str(604), order_by => '4', width => '10%' },
        #{ caption => res_str(605), order_by => '5', width => '10%' },
        #{ caption => res_str(606), order_by => '6', width => '10%' },
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
                    ) OR CURRENT_TIMESTAMP > C.finish_date
            )~],
            params => [$uid]
        };
      
    if ($kw) {
        push @{$where->{cond}}, q~
            (EXISTS (SELECT 1 FROM problem_keywords PK WHERE PK.problem_id = P.id AND PK.keyword_id = ?))~;
        push @{$where->{params}}, $kw;
    }

    my $where_cond = join(' AND ', @{$where->{cond}}) || '1=1';
    # TODO: применить SUM(CASE ...) после обновления FB
    my $c = $dbh->prepare(qq~
        SELECT P.id, P.title, C.title, C.id,
            (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_accepted), 
            (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_wrong_answer), 
            (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_time_limit_exceeded),
            (SELECT COUNT(*) FROM contest_problems CP WHERE CP.problem_id = P.id AND CP.contest_id=?)
        FROM problems P INNER JOIN contests C ON C.id = P.contest_id
        WHERE $where_cond ~ . order_by);
    # interbase bug
    $c->execute(@{$where->{params}}, $cid);

    my $fetch_record = sub($)
    {
        my (
            $pid, $problem_name, $contest_name, $contest_id, $accept_count, $wa_count, $tle_count, $linked
        ) = $_[0]->fetchrow_array
            or return ();
        return ( 
            href_view_problem => url_f('problem_text', pid => $pid),
            href_view_contest => url_function('problems', sid => $sid, cid => $contest_id),
            linked => $linked || !$link,
            problem_id => $pid,
            problem_name => $problem_name, 
            contest_name => $contest_name, 
            accept_count => $accept_count, 
            wa_count => $wa_count,
            tle_count => $tle_count,
        );
    };
         
    attach_listview(url_f('problems', link => $link, kw => $kw), $fetch_record, $c);

    $t->param(
        href_action => url_f($kw ? 'keywords' : 'problems'),
        link => !$contest->is_practice && $link, move => url_param('move') || 0);
    
    $c->finish;
}


sub download_problem
{
    undef $t;

    my $pid = param('download');
    # Если hash уже есть, то файл не вытаскиваем, а выдаём ссылку на имеющийся.
    # Предполагаем, что размер пакета достаточно велик,
    # поэтому имеет смысл выбирать его отдельным запросом.
    my ($hash) = $dbh->selectrow_array(qq~
        SELECT hash FROM problems WHERE id = ?~, undef, $pid);
    my $already_hashed = ensure_problem_hash($pid, \$hash);
    my $fname = "./download/problem_$hash.zip";
    unless($already_hashed && -f $fname)
    {
        my ($zip) = $dbh->selectrow_array(qq~
            SELECT zip_archive FROM problems WHERE id = ?~, undef, $pid);
        CATS::BinaryFile::save(cats_dir() . $fname, $zip);
    }
    print redirect(-uri => $fname);
}


sub upload_source
{
    my ($file) = @_;
    my $src = '';
    use bytes;
    while (read($file, my $buffer, 4096))
    {
        length $src < 32767
            or return msg(10);
        $src .= $buffer;
    }
    #$src or return msg(11);
    return $src;
}


sub problems_submit
{
    # Проверяем параметры заранее, чтобы не делать бесполезных обращений к БД.
    my $pid = param('problem_id')
        or return msg(12);

    my $file = param('source');
    $file ne '' or return msg(9);

    defined param('de_id') or return msg(14);

    unless ($is_jury)
    {
        my ($time_since_start, $time_since_finish, $is_official, $status) = $dbh->selectrow_array(qq~
            SELECT
                CATS_SYSDATE() - $virtual_diff_time - C.start_date,
                CATS_SYSDATE() - $virtual_diff_time - C.finish_date,
                C.is_official, CP.status
            FROM contests C, contest_problems CP
            WHERE CP.contest_id = C.id AND C.id = ? AND CP.problem_id = ?~, {},
            $cid, $pid);

        $time_since_start >= 0
            or return msg(80);
        $time_since_finish <= 0
            or return msg(81);
        !defined $status || $status < $cats::problem_st_disabled
            or return msg(124);

        # во время официального турнира отправка заданий во все остальные временно прекращается
        unless ($is_official && !$is_virtual)
        {
            my ($current_official) = $dbh->selectrow_array(qq~
                SELECT title FROM contests
                  WHERE CATS_SYSDATE() BETWEEN start_date AND finish_date AND is_official = 1~);
            !$current_official
                or return msg(123, $current_official);
        }
    }
    
    my $submit_uid = $uid;
    if (!defined $submit_uid && $contest->is_practice)
    {
        $submit_uid = get_anonymous_uid();
    }

    # Защита от Denial of Service -- запрещаем посылать решения слишком часто
    my $prev = $dbh->selectcol_arrayref(qq~
        SELECT FIRST 2 CATS_SYSDATE() - R.submit_time FROM reqs R
        WHERE R.account_id = ?
        ORDER BY R.submit_time DESC~, {},
        $submit_uid);
    my $SECONDS_PER_DAY = 24*60*60;
    if (($prev->[0] || 1) < 3/$SECONDS_PER_DAY || ($prev->[1] || 1) < 60/$SECONDS_PER_DAY)
    {
        return msg(131);
    }
    
    my $src = upload_source($file) or return;
    my $did = param('de_id');

    if (param('de_id') eq 'by_extension')
    {
        my $de_list = CATS::DevEnv->new($dbh, active_only => 1);
        my $de = $de_list->by_file_extension($file)
            or return msg(13);
        $did = $de->{id};
        $t->param(de_name => $de->{description});
    }

    # Защита от спама и случайных ошибок -- запрещаем повторяющийся исходный код.
    my $source_hash = source_hash($src);
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
        INSERT INTO reqs(
            id, account_id, problem_id, contest_id, 
            submit_time, test_time, result_time, state, received
        ) VALUES(
            ?,?,?,?,CATS_SYSDATE(),CATS_SYSDATE(),CATS_SYSDATE(),?,?)~,
        {},
        $rid, $submit_uid, $pid, $cid, $cats::st_not_processed, 0);

    my $s = $dbh->prepare(qq~
        INSERT INTO sources(req_id, de_id, src, fname, hash) VALUES (?,?,?,?,?)~);
    $s->bind_param(1, $rid);
    $s->bind_param(2, $did);
    $s->bind_param(3, $src, { ora_type => 113 } ); # blob
    $s->bind_param(4, "$file");
    $s->bind_param(5, $source_hash);
    $s->execute;
    $dbh->commit;

    $t->param(solution_submitted => 1, href_console => url_f('console'));
    msg(15);
}


sub problems_submit_std_solution
{
    my $pid = param('problem_id');

    defined $pid
        or return msg(12);

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
                CATS_SYSDATE(), CATS_SYSDATE(), CATS_SYSDATE(), ?, 0)~,
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
    my $retest_pid = param('problem_id')
        or return msg(12);
    my $all_runs = param('all_runs');
    my $runs = $dbh->selectall_arrayref(q~
        SELECT id, account_id FROM reqs
        WHERE contest_id = ? AND problem_id = ? ORDER BY id DESC~,
        { Slice => {} },
        $cid, $retest_pid
    );
    my $count = 0;
    my %accounts = ();
    for (@$runs)
    {
        next if !$all_runs && $accounts{$_->{account_id}};
        $accounts{$_->{account_id}} = 1;
        enforce_request_state(request_id => $_->{id}, state => $cats::st_not_processed)
            and ++$count;
    }
    $dbh->commit;
    return msg(128, $count);
}


sub problem_status_names()
{
    return {
        $cats::problem_st_ready     => res_str(700),
        $cats::problem_st_suspended => res_str(701),
        $cats::problem_st_disabled  => res_str(702),
        $cats::problem_st_hidden    => res_str(703),
    };
}


sub problems_frame_jury_action
{
    $is_jury or return;

    defined param('link_save') and return problems_link_save;
    defined param('new_save') and return problems_new_save;
    defined param('change_status') and return problems_change_status;
    defined param('replace') and return problems_replace;
    defined param('std_solution') and return problems_submit_std_solution;
    defined param('mass_retest') and return problems_mass_retest;
    my $cpid = url_param('delete');
    if (defined $cpid)
    {
        my ($pid, $old_contest) = $dbh->selectrow_array(q~
            SELECT problem_id, contest_id FROM contest_problems WHERE id = ?~, undef,
            $cpid) or return;

        $dbh->do(qq~DELETE FROM contest_problems WHERE id = ?~, undef, $cpid);
        my ($ref_count) = $dbh->selectrow_array(qq~
            SELECT COUNT(*) FROM contest_problems WHERE problem_id = ?~, undef, $pid);
        if ($ref_count)
        {
            # Если на задачу ссылается хотя бы один турнир, переносим все попытки
            # в "главный" турнир. Из главного турнира задача должна удаляться последней.
            # Это ограничение можно обойти, произвольно назначая новый главный турнир.
            my ($new_contest) = $dbh->selectrow_array(q~
                SELECT contest_id FROM problems WHERE id = ?~, undef, $pid);
            ($new_contest != $old_contest) or return msg(136);
            $dbh->do(q~
                UPDATE reqs SET contest_id = ? WHERE problem_id = ? AND contest_id = ?~, undef,
                $new_contest, $pid, $old_contest);
        }
        else
        {
            $dbh->do(qq~DELETE FROM problems WHERE id = ?~, undef, $pid);
        }
        $dbh->commit;
    }
}


sub problem_select_testsets
{
    $is_jury or return;
    my $cpid = param('cpid') or return;
    
    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.id, P.title, CP.id AS cpid, CP.testsets
        FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE CP.id = ?~, undef, $cpid);
    my $testsets = $dbh->selectall_arrayref(q~
        SELECT * FROM testsets WHERE problem_id = ?~, { Slice => {} },
        $problem->{id});

    if (param('save'))
    {
        my %sel;
        @sel{param('sel')} = undef;
        $_->{selected} = exists $sel{$_->{id}} for @$testsets;
        my $ts_list = join ' ', map $_->{name}, grep $_->{selected}, @$testsets;
        $dbh->do(q~
            UPDATE contest_problems SET testsets = ? WHERE id = ?~, undef,
            $ts_list, $problem->{cpid});
        $dbh->commit;
    }
    else
    {
        my %sel;
        @sel{split /\s+/, $problem->{testsets} || ''} = undef;
        $_->{selected} = exists $sel{$_->{name}} for @$testsets;
    }
    
    
    init_template('main_problem_select_testsets.htm');
    $t->param("problem_$_" => $problem->{$_}) for keys %$problem;
    $t->param(testsets => $testsets, href_select_testsets => url_f('problem_select_testsets'));
}

sub problems_frame
{
    my $my_is_team =
        $is_jury || $contest->is_practice ||
        $is_team && $contest->{time_since_finish} - $virtual_diff_time < 0;
    my $show_packages = 1;
    unless ($is_jury)
    {
        $show_packages = $contest->{show_packages};
        my $local_only = $contest->{local_only};
        if ($contest->{time_since_start} < 0)
        {
            init_template('main_problems_inaccessible.htm');
            return msg(130);
        }
        if ($local_only)
        {
            my $is_remote;
            if ($uid)
            { 
                ($is_remote) = $dbh->selectrow_array(qq~
                    SELECT is_remote FROM contest_accounts WHERE contest_id = ? AND account_id = ?~,
                    {}, $cid, $uid);
            }
            if(!defined $is_remote || $is_remote)
            {
                init_template('main_problems_inaccessible.htm');
                return msg(129);
            }
        }
    }

    $is_jury && defined url_param('new') and return problems_new_frame;
    $is_jury && defined url_param('link') and return problems_all_frame;
    defined url_param('kw') and return problems_all_frame;

    defined param('download') && $show_packages and return download_problem;

    init_listview_template("problems$cid" . ($uid || ''), 'problems', 'main_problems.htm');
    problems_frame_jury_action;

    if (defined param('submit'))
    {
        problems_submit;
    }

    my @cols = (
        { caption => res_str(602), order_by => '3', width => '30%' },
        ($is_jury ?
        (
            { caption => res_str(632), order_by => '10', width => '10%' }, # статус
            { caption => res_str(605), order_by => '14', width => '10%' }, # набор тестов
            { caption => res_str(635), order_by => '12', width => '5%' }, # кто изменил
            { caption => res_str(634), order_by => '11', width => '10%' }, # дата изменения
        )
        : ()
        ),
        ($contest->is_practice ?
        { caption => res_str(603), order_by => '4', width => '20%' } : ()
        ),
        { caption => res_str(604), order_by => '5', width => '10%' },
    );
    define_columns(url_f('problems'), 0, 0, [ @cols ]);

    my $reqs_count_sql = 'SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state =';
    my $account_condition = $contest->is_practice ? '' : ' AND D.account_id = ?';
    my $select_code = $contest->is_practice ? '' : q~CP.code || ' - ' || ~;
    my $hidden_problems = $is_jury ? '' : " AND (CP.status IS NULL OR CP.status < $cats::problem_st_hidden)";
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            ${select_code}P.title AS problem_name, OC.title AS contest_name,
            ($reqs_count_sql $cats::st_accepted$account_condition) AS accepted_count,
            ($reqs_count_sql $cats::st_wrong_answer$account_condition) AS wrong_answer_count,
            ($reqs_count_sql $cats::st_time_limit_exceeded$account_condition) AS time_limit_count,
            P.contest_id - CP.contest_id AS is_linked,
            OC.id AS original_contest_id, CP.status,
            CATS_DATE(P.upload_date) AS upload_date,
            (SELECT A.login FROM accounts A WHERE A.id = P.last_modified_by) AS last_modified_by,
            SUBSTRING(P.explanation FROM 1 FOR 1) AS has_explanation,
            CP.testsets
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
        my $aid = $uid || 0; # на случай анонимного пользователя
        # OldParamOrdering -- опять баг с порядком параметров
        # ORDER BY subselect требует повторного указания параметра
        $sth->execute($cid, $aid, $aid, $aid, (order_by =~ /^ORDER BY\s+(5|6|7)\s+/ ? ($aid) : ()));
    }
    
    my @status_list;
    if ($is_jury)
    {
        my $n = problem_status_names();
        for (sort keys %$n)
        {
            push @status_list, { id => $_, name => $n->{$_} }; 
        }
        $t->param(
            status_list => \@status_list,
            editable => 1
        );
    }

    my $fetch_record = sub($)
    {            
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
        my $psn = problem_status_names();
        return (
            href_delete   => url_f('problems', 'delete' => $c->{cpid}),
            href_change_status => url_f('problems', 'change_status' => $c->{cpid}),
            href_replace  => url_f('problems', replace => $c->{cpid}),
            href_download => url_f('problems', download => $c->{pid}),
            href_compare_tests => $is_jury && url_f('compare_tests', pid => $c->{pid}),
            href_original_contest =>
                url_function('problems', sid => $sid, cid => $c->{original_contest_id}, set_contest => 1),
            show_packages => $show_packages,
            is_practice => $contest->is_practice,
            editable => $is_jury,
            status => $c->{status},
            disabled => !$is_jury && $c->{status} == $cats::problem_st_disabled,
            is_team => $my_is_team,
            href_view_problem => url_f('problem_text', cpid => $c->{cpid}),
            href_explanation => $show_packages && $c->{has_explanation} ?
                url_f('problem_text', cpid => $c->{cpid}, explain => 1) : '',
            problem_id => $c->{pid},
            problem_name => $c->{problem_name},
            is_linked => $c->{is_linked},
            contest_name => $c->{contest_name},
            accept_count => $c->{accepted_count},
            wa_count => $c->{wrong_answer_count},
            tle_count => $c->{time_limit_count},
            upload_date => $c->{upload_date},
            last_modified_by => $c->{last_modified_by},
            testsets => $c->{testsets} || '*',
            href_select_testsets => url_f('problem_select_testsets', cpid => $c->{cpid}),
            status_list => [
                map {{ id => $_, name => $psn->{$_}, selected => $c->{status} == $_ }} sort keys %$psn
            ],
        );
    };
            
    attach_listview(url_f('problems'), $fetch_record, $sth);

    $sth->finish;

    my $de_list = CATS::DevEnv->new($dbh, active_only => 1);
    my @de = (
        { de_id => 'by_extension', de_name => res_str(536) },
        map {{ de_id => $_->{id}, de_name => $_->{description} }} @{$de_list->{_de_list}} );
    
    my @submenu = ();
    unless ($contest->is_practice)
    {
        my %pt_url = ( item_name => res_str(538), item_target => '_blank' );
        push @submenu,
            $is_jury ?
            (
                { %pt_url, href_item => url_f('problem_text', nospell => 1, nokw => 1, notime => 1) },
                { %pt_url, href_item => url_f('problem_text'), item_name => res_str(555) },
            ):
            (
                { %pt_url, href_item => CATS::StaticPages::url_static('problem_text', cid => $cid) }
            );
    }
    
    if ($is_jury)
    {
        push @submenu, (
            { href_item => url_f('problems', new => 1), item_name => res_str(539) },
            { href_item => url_f('problems', link => 1), item_name => res_str(540) },
            { href_item => url_f('problems', link => 1, move => 1), item_name => res_str(551) }
        );
    }

    $t->param(submenu => \@submenu);
    $t->param(is_team => $my_is_team, is_practice => $contest->is_practice, de_list => \@de);
}


sub compare_tests_frame
{
    init_template('main_compare_tests.htm');
    $is_jury or return;
    my ($pid) = param('pid') or return;
    my ($pt) = $dbh->selectrow_array(q~
        SELECT title FROM problems WHERE id = ?~, undef,
        $pid);
    $pt or return;
    $t->param(problem_title => $pt);
    
    my $totals = $dbh->selectall_hashref(qq~
        SELECT
            SUM(CASE rd.result WHEN $cats::st_accepted THEN 1 ELSE 0 END) AS passed_count,
            SUM(CASE rd.result WHEN $cats::st_accepted THEN 0 ELSE 1 END) AS failed_count,
            rd.test_rank
        FROM reqs r
            INNER JOIN req_details rd ON rd.req_id = r.id
            INNER JOIN contest_accounts ca ON
                ca.contest_id = r.contest_id AND ca.account_id = r.account_id
        WHERE
            r.problem_id = ? AND r.contest_id = ? AND ca.is_jury = 0
        GROUP BY rd.test_rank~, 'test_rank', { Slice => {} },
        $pid, $cid) or return;

    my $c = $dbh->selectall_arrayref(qq~
        SELECT COUNT(*) AS cnt, rd1.test_rank AS r1, rd2.test_rank AS r2
            FROM reqs r
            INNER JOIN req_details rd1 ON rd1.req_id = r.id
            INNER JOIN req_details rd2 ON rd2.req_id = r.id
            INNER JOIN contest_accounts ca ON
                ca.contest_id = r.contest_id AND ca.account_id = r.account_id
            WHERE
                rd1.test_rank <> rd2.test_rank AND
                rd1.result = $cats::st_accepted AND
                rd2.result <> $cats::st_accepted AND
                r.problem_id = ? AND r.contest_id = ? AND ca.is_jury = 0
            GROUP BY rd1.test_rank, rd2.test_rank~, { Slice => {} },
        $pid, $cid);

    my $h = {};
    $h->{$_->{r1}}->{$_->{r2}} = $_->{cnt} for @$c;
    my $size = max(keys %$totals) || 0;
    my $cm = [
        map {
            my $hr = $h->{$_} || {};
            { data => [ map {{ n => ($hr->{$_} || 0) }} 1..$size ], %{$totals->{$_} || {}} }
        } 1..$size
    ];

    my (@equiv_tests, @simple_tests, @hard_tests);
    for my $i (1..$size)
    {
        my ($too_simple, $too_hard) = (1, 1);
        for my $j (1..$size)
        {
            my $zij = !exists $h->{$i} || !exists $h->{$i}->{$j};
            my $zji = !exists $h->{$j} || !exists $h->{$j}->{$i};
            push @equiv_tests, { t1 => $i, t2 => $j } if $zij && $zji && $j > $i;
            $too_simple &&= $zji;
            $too_hard &&= $zij;
        }
        push @simple_tests, { t => $i } if $too_simple;
        push @hard_tests, { t => $i } if $too_hard;
    }

    $t->param(
        comparision_matrix => $cm,
        equiv_tests => \@equiv_tests,
        simple_tests => \@simple_tests,
        hard_tests => \@hard_tests,
    );
}


sub users_new_frame 
{
    init_template('main_users_new.htm');
    $t->param(login => generate_login);
    $t->param(countries => \@cats::countries, href_action => url_f('users'));    
}


sub user_param_names ()
{
    qw(login team_name capitan_name email country motto home_page icq_number)
}


sub user_validate_params
{
    my ($up, %p) = @_;

    $up->{login} && length $up->{login} <= 100
        or return msg(101);

    $up->{team_name} && length $up->{team_name} <= 100
        or return msg(43);

    length $up->{capitan_name} <= 100
        or return msg(45);

    length $up->{motto} <= 200
        or return msg(44);

    length $up->{home_page} <= 100
        or return msg(48);

    length $up->{icq_number} <= 100
        or return msg(47);

    if ($p{validate_password})
    {
        $up->{password1} ne '' && length $up->{password1} <= 100
            or return msg(102);

        $up->{password1} eq $up->{password2}
            or return msg(33);
        msg(85);
    }
    return 1;
}


# Администратор добавляет нового пользователя в текущий турнир.
sub users_new_save
{
    $is_jury or return;

    my %up = map { $_ => (param($_) || '') } user_param_names(), qw(password1 password2);
    
    user_validate_params(\%up, validate_password => 1) or return;

    $dbh->selectrow_array(qq~SELECT COUNT(*) FROM accounts WHERE login=?~, {}, $up{login})
        and return msg(103);

    my ($training_id) = $dbh->selectrow_array(qq~SELECT id FROM contests WHERE ctype = 1~)
        or return msg(105);

    my $aid = new_id;
    $dbh->do(qq~
        INSERT INTO accounts (
            id, srole, passwd, ~ . join (', ', user_param_names()) . qq~
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?)~, {},
        $aid, $cats::srole_user, $up{password1},
        @up{user_param_names()}
    );

    insert_ooc_user(account_id => $aid);
    if ($cid != $training_id)
    {
        insert_ooc_user(contest_id => $training_id, account_id => $aid);
    }
 
    $dbh->commit;       
}


sub users_edit_frame 
{      
    my $id = url_param('edit');

    init_template('main_users_edit.htm');

    my $up = $dbh->selectrow_hashref(qq~
        SELECT login, team_name, capitan_name, motto, country, email, home_page, icq_number
            FROM accounts WHERE id = ?~, { Slice => {} },
        $id
    ) or return;

    my $countries = \@cats::countries;

    $up->{country} ||= $countries->[0]->{id};
    for (@$countries)
    {
        $_->{selected} = $_->{id} eq $up->{country};
    }

    $t->param(%$up, id => $id, countries => $countries, href_action => url_f('users'));
}


sub users_edit_save
{
    my %up = map { $_ => (param($_) || '') } user_param_names(), qw(password1 password2);
    my $set_password = param_on('set_password');
    my $id = param('id');

    user_validate_params(\%up, validate_password => $set_password) or return;

    $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM accounts WHERE id <> ? AND login = ?~, {}, $id, $up{login}
    ) and return msg(103);
 
    $dbh->do(qq~
        UPDATE accounts
            SET ~ . join (', ', map "$_ = ?", user_param_names()) . qq~
            WHERE id = ?~, {},
        @up{user_param_names()}, $id);
    $dbh->commit;       

    if ($set_password)
    {        
        $dbh->do(qq~UPDATE accounts SET passwd = ? WHERE id = ?~, {}, $up{password1}, $id);
        $dbh->commit;
    }
}


sub users_send_message
{
    my %p = @_;
    $p{'message'} ne '' or return;
    my $s = $dbh->prepare(qq~
        INSERT INTO messages (id, send_time, text, account_id, received)
            VALUES (?, CATS_SYSDATE(), ?, ?, 0)~
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


sub users_send_broadcast
{
    my %p = @_;
    $p{'message'} ne '' or return;
    my $s = $dbh->prepare(qq~
        INSERT INTO messages (id, send_time, text, account_id, broadcast)
            VALUES(?, CATS_SYSDATE(), ?, NULL, 1)~
    );
    $s->bind_param(1, new_id);
    $s->bind_param(2, $p{'message'}, { ora_type => 113 });
    $s->execute;
    $s->finish;
}


sub users_register
{
    my ($login) = @_;
    defined $login && $login ne ''
        or return msg(118);

    my ($aid) = $dbh->selectrow_array(qq~SELECT id FROM accounts WHERE login=?~, {}, $login);
    $aid or return msg(118, $login);
    !get_registered_contestant(contest_id => $cid, account_id => $aid)
        or return msg(120, $login);

    insert_ooc_user(account_id => $aid, is_remote => 1);
    $dbh->commit;
    msg(119, $login);
}


sub users_frame 
{   
    # hack для туфанова и олейникова
    #$is_jury ||= $is_root; 
    if (defined url_param('delete') && $is_jury)
    {
        my $caid = url_param('delete');
        my ($aid, $srole) = $dbh->selectrow_array(qq~
            SELECT A.id, A.srole FROM accounts A, contest_accounts CA
                WHERE A.id=CA.account_id AND CA.id=?~, {},
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

    if (defined url_param('new') && $is_jury)
    {        
        users_new_frame;
        return;
    }

    if (defined url_param('edit') && $is_jury)
    {        
        users_edit_frame;
        return;
    }


    init_listview_template( "users$cid" . ($uid || ''), 'users', 'main_users.htm' );      

    $t->param(messages => $is_jury);
    
    if (defined param('new_save') && $is_jury)       
    {
        users_new_save;
    }

    if (defined param('edit_save') && $is_jury)       
    {
        users_edit_save;
    }

    if (defined param('save_attributes') && $is_jury)
    {
        for (split(':', param('user_set')))
        {
            my $jury = param_on("jury$_");
            my $ooc = param_on("ooc$_");
            my $remote = param_on("remote$_");
            my $hidden = param_on("hidden$_");

            my $srole = $dbh->selectrow_array(qq~
                SELECT srole FROM accounts
                    WHERE id IN (SELECT account_id FROM contest_accounts WHERE id=?)~, {},
                $_
            );
            $jury = 1 if !$srole;

            $dbh->do(qq~
                UPDATE contest_accounts
                    SET is_jury=?, is_hidden=?, is_remote=?, is_ooc=? WHERE id=?~, {},
                $jury, $hidden, $remote, $ooc, $_
            );
        }
        $dbh->commit;
    }

    if (defined param('register_new') && $is_jury)
    {
        users_register(param('login_to_register'));
    }
    
    if (defined param('send_message') && $is_jury)
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

    my @cols;
    if ($is_jury)
    {
        @cols = ( { caption => res_str(616), order_by => '4', width => '15%' } );
    }

    push @cols,
      ( { caption => res_str(608), order_by => '5', width => '20%' } );

    if ($is_jury)
    {
        push @cols,
            (
              { caption => res_str(611), order_by => '6', width => '10%' },
              { caption => res_str(612), order_by => '7', width => '10%' },
              { caption => res_str(613), order_by => '8', width => '10%' },
              { caption => res_str(614), order_by => '9', width => '10%' } );
    }

    push @cols,
      ( { caption => res_str(607), order_by => '3', width => '10%' },
        { caption => res_str(609), order_by => '12', width => '10%' } );


    push @cols,
        ( { caption => res_str(632), order_by => '10', width => '10%' } );

    define_columns(url_f('users'), $is_jury ? 3 : 2, 1, [ @cols ] );

    my $fields =
        'A.id, CA.id, A.country, A.login, A.team_name, ' . 
        'CA.is_jury, CA.is_ooc, CA.is_remote, CA.is_hidden, CA.is_virtual, A.motto';
    my $sql = qq~
        SELECT $fields, COUNT(DISTINCT R.problem_id)
        FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id
            INNER JOIN contests C ON CA.contest_id = C.id
            LEFT JOIN reqs R ON
                R.state = $cats::st_accepted AND R.account_id=A.id AND R.contest_id=C.id%s
        WHERE C.id=?%s GROUP BY $fields
        ~.order_by;
    if ($is_jury)
    {
        $sql = sprintf $sql, '', '';
    }
    else
    {
        $sql = sprintf $sql,
            ' AND (R.submit_time < C.freeze_date OR C.defreeze_date < CATS_SYSDATE())',
            ' AND CA.is_hidden=0';
    }
    my $c = $dbh->prepare($sql);
    $c->execute($cid);

    my $fetch_record = sub($)
    {            
        my (
            $aid, $caid, $country_abb, $login, $team_name, $jury,
            $ooc, $remote, $hidden, $virtual, $motto, $accepted
        ) = $_[0]->fetchrow_array
            or return ();
        my ($country, $flag) = get_flag($country_abb);
        return ( 
            href_delete => url_f('users', delete => $caid),
            href_edit => url_f('users', edit => $aid),
            motto => $motto,
            id => $caid,
            login => $login, 
            editable => $is_jury,
            messages => $is_jury,
            team_name => $team_name,
            country => $country,
            flag => $flag,
            accepted => $accepted,
            jury => $jury,
            hidden => $hidden,
            ooc => $ooc,
            remote => $remote,
            virtual => $virtual
         );
    };

    attach_listview(url_f('users'), $fetch_record, $c);

    if ($is_jury)
    {
        $t->param(
            submenu => [ { href_item => url_f('users', new => 1), item_name => res_str(541) } ],
            editable => 1
        );
    }

    $c->finish;
}


sub registration_frame
{
    init_template('main_registration.htm');

    $t->param(countries => [ @cats::countries ], href_login => url_f('login'));

    defined param('register')
        or return;
    
    my %up = map { $_ => (param($_) || '') } user_param_names(), qw(password1 password2);
    user_validate_params(\%up, validate_password => 1) or return;

    if ($dbh->selectrow_array(qq~SELECT COUNT(*) FROM accounts WHERE login=?~, {}, $up{login}))
    {
        msg(103);
        return;       
    }

    my $training_contests = $dbh->selectall_arrayref(qq~
        SELECT id, closed FROM contests WHERE ctype = 1~, { Slice => {} });
    0 == grep $_->{closed}, @$training_contests
        or return msg(105);
        
    my $aid = new_id;
    $dbh->do(qq~
        INSERT INTO accounts (
            id, srole, passwd, ~ . join (', ', user_param_names()) . qq~
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?)~, {},
        $aid, $cats::srole_user, $up{password1},
        @up{user_param_names()}
    );
    insert_ooc_user(contest_id => $_->{id}, account_id => $aid) for @$training_contests;
         
    $dbh->commit;
    $t->param(successfully_registred => 1);
}


sub settings_save
{
    my %up = map { $_ => (param($_) || '') } user_param_names(), qw(password1 password2);
    my $set_password = param_on('set_password');

    # Если команда участвовала в официальных соревнованиях, запретить изменять её название.
    my ($official_contest) = $dbh->selectrow_array(qq~
        SELECT FIRST 1 C.title FROM contests C
            INNER JOIN contest_accounts CA ON CA.contest_id = C.id
            INNER JOIN accounts A ON A.id = CA.account_id
            WHERE C.is_official = 1 AND CA.is_ooc = 0 AND CA.is_jury = 0 AND
            C.finish_date < CURRENT_TIMESTAMP AND A.id = ?~, undef,
        $uid
    );
    if ($official_contest) {
        my ($old_team_name) = $dbh->selectrow_array(qq~
            SELECT team_name FROM accounts WHERE id = ?~, undef,
            $uid);
        $old_team_name eq $up{team_name}
            or return msg(86, $official_contest);
    }

    user_validate_params(\%up, validate_password => $set_password) or return;

    $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM accounts WHERE id <> ? AND login = ?~, {}, $uid, $up{login}
    ) and return msg(103);
 
    if ($set_password) {
        $up{passwd} = $up{password1};
    }
    delete @up{qw(password1 password2)};
    $dbh->do(_u $sql->update('accounts', \%up, { id => $uid }));
    $dbh->commit;
}


sub settings_frame
{      
    init_template('main_settings.htm');

    if (defined param('edit_save') && $is_team)
    {
        settings_save;
    }

    my $settings = $dbh->selectrow_hashref(qq~
        SELECT login, team_name, capitan_name, motto, country, email, home_page, icq_number
        FROM accounts WHERE id = ?~, { Slice => {} },
        $uid
    );

    my $countries = [ @cats::countries ];

    if (defined $settings->{country})
    {
        $_->{selected} = $_->{id} eq $settings->{country}
            for @$countries;
    }

    $t->param(countries => $countries, href_action => url_f('users'), %$settings);
}


sub reference_names()
{
    (
        { name => 'compilers', new => 542, item => 517 },
        { name => 'judges', new => 543, item => 511 },
        { name => 'keywords', new => 550, item => 549 },
    )
}


sub references_menu
{
    my ($ref_name) = @_;

    my @result;
    for (reference_names())
    {
        my $sel = $_->{name} eq $ref_name;
        push @result, { href_item => url_f($_->{name}), item_name => res_str($_->{item}), selected => $sel };
        if ($sel && $is_root)
        {
            unshift @result, 
                { href_item => url_f($_->{name}, new => 1), item_name => res_str($_->{new}) };
        }
    }
    @result;
}


sub compilers_new_frame
{
    init_template('main_compilers_new.htm');
    $t->param(href_action => url_f('compilers'));
}


sub compilers_new_save
{
    my $code = param('code');
    my $description = param('description');
    my $supported_ext = param('supported_ext');
    my $locked = param_on('locked');
            
    $dbh->do(qq~
        INSERT INTO default_de(id, code, description, file_ext, in_contests) VALUES(?,?,?,?,?)~, {}, 
        new_id, $code, $description, $supported_ext, !$locked);
    $dbh->commit;   
}


sub compilers_edit_frame
{
    init_template('main_compilers_edit.htm');

    my $id = url_param('edit');

    my ($code, $description, $supported_ext, $in_contests) =
        $dbh->selectrow_array(qq~
            SELECT code, description, file_ext, in_contests FROM default_de WHERE id=?~, {}, $id);

    $t->param(
        id => $id,
        code => $code, 
        description => $description, 
        supported_ext => $supported_ext, 
        locked => !$in_contests,
        href_action => url_f('compilers'));
}


sub compilers_edit_save
{
    my $code = param('code');
    my $description = param('description');
    my $supported_ext = param('supported_ext');
    my $locked = param_on('locked');
    my $id = param('id');
            
    $dbh->do(qq~
        UPDATE default_de SET code=?, description=?, file_ext=?, in_contests=? WHERE id=?~, {}, 
             $code, $description, $supported_ext, !$locked, $id);
    $dbh->commit;   
}


sub compilers_frame
{    
    if ($is_jury)
    {
        if ($is_root && defined url_param('delete')) # extra security
        {
            my $deid = url_param('delete');
            $dbh->do(qq~DELETE FROM default_de WHERE id=?~, {}, $deid);
            $dbh->commit;       
        }
        
        defined url_param('new') and return compilers_new_frame;
        defined url_param('edit') and return compilers_edit_frame;
    }

    init_listview_template("compilers$cid" . ($uid || ''), 'compilers', 'main_compilers.htm');

    if ($is_jury)
    {
        defined param('new_save') and compilers_new_save;
        defined param('edit_save') and compilers_edit_save;
    }

    define_columns(url_f('compilers'), 0, 0, [
        { caption => res_str(619), order_by => '2', width => '10%' },
        { caption => res_str(620), order_by => '3', width => '40%' },
        { caption => res_str(621), order_by => '4', width => '20%' },
        ($is_jury ? { caption => res_str(622), order_by => '5', width => '10%' } : ())
    ]);

    my $where = $is_jury ? '' : ' WHERE in_contests = 1';
    my $c = $dbh->prepare(qq~
        SELECT id, code, description, file_ext, in_contests
        FROM default_de$where ~.order_by);
    $c->execute;

    my $fetch_record = sub($)
    {            
        my ($did, $code, $description, $supported_ext, $in_contests) = $_[0]->fetchrow_array
            or return ();
        return ( 
            editable => $is_jury, did => $did, code => $code, 
            description => $description,
            supported_ext => $supported_ext,
            locked => !$in_contests,
            href_edit => url_f('compilers', edit => $did),
            href_delete => url_f('compilers', 'delete' => $did));
    };
    attach_listview(url_f('compilers'), $fetch_record, $c);

    if ($is_jury)
    {
        $t->param(submenu => [ references_menu('compilers') ], editable => 1);
    }
}


sub judges_new_frame
{
    init_template('main_judges_new.htm');
    $t->param(href_action => url_f('judges'));
}


sub judges_new_save
{
    my $judge_name = param('judge_name');
    my $locked = param_on('locked');
    
    $judge_name ne '' && length $judge_name <= 20
        or return msg(5);
    
    $dbh->do(qq~
        INSERT INTO judges (
            id, nick, accept_contests, accept_trainings, lock_counter, is_alive, alive_date
        ) VALUES (?, ?, 1, 1, ?, 0, CATS_SYSDATE())~, {}, 
        new_id, $judge_name, $locked ? -1 : 0);
    $dbh->commit;
}


sub judges_edit_frame
{
    init_template('main_judges_edit.htm');

    my $jid = url_param('edit');
    my ($judge_name, $lock_counter) = $dbh->selectrow_array(qq~
        SELECT nick, lock_counter FROM judges WHERE id=?~, {}, $jid);
    $t->param(id => $jid, judge_name => $judge_name, locked => $lock_counter, href_action => url_f('judges'));
}


sub judges_edit_save
{
    my $jid = param('id');
    my $judge_name = param('judge_name') || '';
    my $locked = param_on('locked');
    
    $judge_name ne '' && length $judge_name <= 20
        or return msg(5);
  
    $dbh->do(qq~
        UPDATE judges SET nick = ?, lock_counter = ? WHERE id = ?~, {},
        $judge_name, $locked ? -1 : 0, $jid);
    $dbh->commit;
}


sub judges_frame 
{
    $is_jury or return;
 
    if (defined url_param('delete'))
    {
        my $jid = url_param('delete');
        $dbh->do(qq~DELETE FROM judges WHERE id=?~, {}, $jid);
        $dbh->commit;
    }

    $is_root && defined url_param('new') and return judges_new_frame;
    $is_root && defined url_param('edit') and return judges_edit_frame;

    init_listview_template("judges$cid" . ($uid || ''), 'judges', 'main_judges.htm');

    $is_root && defined param('new_save') and judges_new_save;
    $is_root && defined param('edit_save') and judges_edit_save;

    define_columns(url_f('judges'), 0, 0, [
        { caption => res_str(625), order_by => '2', width => '65%' },
        { caption => res_str(626), order_by => '3', width => '10%' },
        { caption => res_str(633), order_by => '4', width => '15%' },
        { caption => res_str(627), order_by => '5', width => '10%' }
    ]);

    my $c = $dbh->prepare(qq~
        SELECT id, nick, is_alive, CATS_DATE(alive_date), lock_counter
            FROM judges ~.order_by);
    $c->execute;

    my $fetch_record = sub($)
    {            
        my ($jid, $judge_name, $is_alive, $alive_date, $lock_counter) = $_[0]->fetchrow_array
            or return ();
        return ( 
            editable => $is_root,
            jid => $jid, judge_name => $judge_name, 
            locked => $lock_counter,
            is_alive => $is_alive,
            alive_date => $alive_date,
            href_edit=> url_f('judges', edit => $jid),
            href_delete => url_f('judges', 'delete' => $jid)
        );
    };
             
    attach_listview(url_f('judges'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('judges') ], editable => 1);
    
    my ($not_processed) = $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM reqs WHERE state = ?~, undef,
        $cats::st_not_processed);
    $t->param(not_processed => $not_processed);
    
    $dbh->do(qq~
        UPDATE judges SET is_alive = 0, alive_date = CATS_SYSDATE() WHERE is_alive = 1~);
    $dbh->commit;
}


sub keywords_fields () { qw(name_ru name_en code) }


sub keywords_new_frame
{
    init_template('main_keywords_new.htm');
    $t->param(href_action => url_f('keywords'));
}


sub keywords_new_save
{
    my %p = map { $_ => (param($_) || '') } keywords_fields();
    
    $p{name_en} ne '' && 0 == grep length $p{$_} > 200, keywords_fields()
        or return msg(84);
    
    my $field_names = join ', ', keywords_fields();
    $dbh->do(qq~
        INSERT INTO keywords (id, $field_names) VALUES (?, ?, ?, ?)~, {}, 
        new_id, @p{keywords_fields()});
    $dbh->commit;
}


sub keywords_edit_frame
{
    init_template('main_keywords_edit.htm');

    my $kwid = url_param('edit');
    my $kw = $dbh->selectrow_hashref(qq~SELECT * FROM keywords WHERE id=?~, {}, $kwid);
    $t->param(%$kw, href_action => url_f('keywords'));
}


sub keywords_edit_save
{
    my $kwid = param('id');
    my %p = map { $_ => (param($_) || '') } keywords_fields();

    $p{name_en} ne '' && 0 == grep(length $p{$_} > 200, keywords_fields())
        or return msg(84);

    my $set = join ', ', map "$_ = ?", keywords_fields();
    $dbh->do(qq~
        UPDATE keywords SET $set WHERE id = ?~, {}, 
        @p{keywords_fields()}, $kwid);
    $dbh->commit;
}


sub keywords_frame
{
    if ($is_root)
    {
        if (defined url_param('delete'))
        {
            my $kwid = url_param('delete');
            $dbh->do(qq~DELETE FROM keywords WHERE id = ?~, {}, $kwid);
            $dbh->commit;
        }

        defined url_param('new') and return keywords_new_frame;
        defined url_param('edit') and return keywords_edit_frame;
    }
    init_listview_template('keywords' . ($uid || ''), 'keywords', 'main_keywords.htm');

    $is_root && defined param('new_save') and keywords_new_save;
    $is_root && defined param('edit_save') and keywords_edit_save;

    define_columns(url_f('keywords'), 0, 0, [
        { caption => res_str(638), order_by => '2', width => '31%' },
        { caption => res_str(636), order_by => '3', width => '31%' },
        { caption => res_str(637), order_by => '4', width => '31%' },
    ]);

    my $c = $dbh->prepare(qq~
        SELECT id, code, name_ru, name_en FROM keywords ~.order_by);
    $c->execute;

    my $fetch_record = sub($)
    {
        my ($kwid, $code, $name_ru, $name_en) = $_[0]->fetchrow_array
            or return ();
        return ( 
            editable => $is_root,
            kwid => $kwid, code => $code, name_ru => $name_ru, name_en => $name_en,
            href_edit=> url_f('keywords', edit => $kwid),
            href_delete => url_f('keywords', 'delete' => $kwid),
            href_view_problems => url_f('problems', kw => $kwid),
        );
    };

    attach_listview(url_f('keywords'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('keywords') ], editable => 1) if $is_root;
}


sub send_message_box_frame
{
    init_template('main_send_message_box.htm');
    return unless $is_jury;

    my $caid = url_param('caid');

    my $aid = $dbh->selectrow_array(qq~SELECT account_id FROM contest_accounts WHERE id=?~, {}, $caid);
    my $team = $dbh->selectrow_array(qq~SELECT team_name FROM accounts WHERE id=?~, {}, $aid);

    $t->param(team => $team);

    if (defined param('send'))
    {
        my $message_text = param('message_text');

        my $s = $dbh->prepare(qq~
            INSERT INTO messages (id, send_time, text, account_id, received)
                VALUES (?, CATS_SYSDATE(), ?, ?, 0)~);
        $s->bind_param(1, new_id);
        $s->bind_param(2, $message_text, { ora_type => 113 });
        $s->bind_param(3, $caid);
        $s->execute;
        $dbh->commit;
        $t->param(sent => 1);
    }
}


sub answer_box_frame
{
    init_template('main_answer_box.htm');

    my $qid = url_param('qid');

    my $r = $dbh->selectrow_hashref(qq~
        SELECT
            Q.account_id AS caid, CA.account_id AS aid, A.login, A.team_name,
            CATS_DATE(Q.submit_time) AS submit_time, Q.question, Q.clarified, Q.answer
        FROM questions Q
            INNER JOIN contest_accounts CA ON CA.id = Q.account_id
            INNER JOIN accounts A ON A.id = CA.account_id
        WHERE Q.id = ?~, { Slice => {} },
        $qid);

    $t->param(team_name => $r->{team_name});

    if (defined param('clarify') && (my $a = param('answer_text')))
    {
        $r->{answer} ||= '';
        $r->{answer} .= " $a";

        my $s = $dbh->prepare(qq~
            UPDATE questions
                SET clarification_time = CATS_SYSDATE(), answer = ?, received = 0, clarified = 1
                WHERE id = ?~);
        $s->bind_param(1, $r->{answer}, { ora_type => 113 } );
        $s->bind_param(2, $qid);
        $s->execute;
        $dbh->commit;
        $t->param(clarified => 1);
    }
    else
    {
        $t->param(
            submit_time => $r->{submit_time},
            question_text => $r->{question},
            answer => $r->{answer});
    }
}


sub source_encodings { {'UTF-8' => 1, 'WINDOWS-1251' => 1, 'KOI8-R' => 1, 'CP866' => 1} }

sub source_links
{
    my ($si, $is_jury) = @_;
    my ($current_link) = url_param('f') || '';
    
    $si->{href_contest_problems} =
        url_function('problems', cid => $si->{contest_id}, sid => $sid);
    for (qw/run_details view_source run_log download_source/)
    {
        $si->{'href_' . ($_ eq $current_link ? 'current_link' : $_)} = url_f($_, rid => $si->{req_id});
    }
    $si->{is_jury} = $is_jury;
    $t->param(is_jury => $is_jury);
    if ($is_jury && $si->{judge_id})
    {
        $si->{judge_name} = get_judge_name($si->{judge_id});
    }
    my $se = param('src_enc') || param('comment_enc') || '';
    $t->param(source_encodings =>
        [ map {{ enc => $_, selected => $_ eq $se }} keys %{source_encodings()} ]);
}


sub run_details_frame
{
    init_template('main_run_details.htm');

    my $rid = url_param('rid');

    my $si = get_sources_info(request_id => $rid) or return;
    $t->param(sources_info => [$si]);

    my $is_jury = is_jury_in_contest(contest_id => $si->{contest_id});

    $is_jury || $uid == $si->{account_id}
        or return;

    my $contest = $dbh->selectrow_hashref(qq~
        SELECT
            run_all_tests, show_all_tests, show_test_resources, show_checker_comment
            FROM contests WHERE id = ?~, { Slice => {} },
        $si->{contest_id}
    );

    my $jury_view = $is_jury && !url_param('as_user');
    $contest->{$_} ||= $jury_view
        for qw(show_all_tests show_test_resources show_checker_comment);

    my $points = [];

    if ($contest->{show_all_tests})
    {
        $points = $dbh->selectcol_arrayref(qq~
            SELECT points FROM tests WHERE problem_id = ? ORDER BY rank~, {},
            $si->{problem_id});
    }
    my $show_points = 0 != grep defined $_ && $_ > 0, @$points;

    source_links($si, $is_jury);
    $t->param(%$contest, show_points => $show_points);

    my %run_details;
    my $rd_fields = join ', ', (
         qw(test_rank result),
         ($contest->{show_test_resources} ? qw(time_used memory_used disk_used) : ()),
         ($contest->{show_checker_comment} ? qw(checker_comment) : ()),
    );

    my $c = $dbh->prepare(qq~
        SELECT $rd_fields FROM req_details WHERE req_id = ? ORDER BY test_rank~);
    $c->execute($rid);
    my $last_test = 0;
    
    while (my $row = $c->fetchrow_hashref())
    {
        # На случай, если в БД не well-formed utf8
        if ($contest->{show_checker_comment})
        {
            my $d = $row->{checker_comment} || '';
            my $enc = param('comment_enc') || '';
            source_encodings()->{$enc} or $enc = 'UTF-8';
            $row->{checker_comment} = Encode::decode($enc, $d, Encode::FB_QUIET);
            $row->{checker_comment} .= '...' if $d ne '';
        }
        
        my $prev_test = $last_test;
        my $accepted = $row->{result} == $cats::st_accepted;
        
        $run_details{$last_test = $row->{test_rank}} =
        {
            state_to_display($row->{result}),
            map({ $_ => $contest->{$_} }
                qw(show_test_resources show_checker_comment)),
            %$row,
            show_points => $show_points,
            points => ($accepted ? $points->[$row->{test_rank} - 1] : 0),
        };
        # Тесты запускаются в случайном порядке.
        # Если участник просмотрит таблицу результатов в процессе тестирования решения,
        # он может увидеть результат 'OK' для теста с номером, бОльшим, чем первый
        # не прошедший тест. Поэтому вывод результатов прекращаем на первом
        # не прошедшем ИЛИ не ещё запущенном тесте.
        last if
            !$contest->{show_all_tests} &&
            (!$accepted || $prev_test != $last_test - 1); 
    }
    # Выводить 'not processed' для тестов, которые вообще не запускались.
    if ($contest->{show_all_tests} && !$contest->{run_all_tests})
    {
        $last_test = @$points;
    }
    my %testset;
    @testset{CATS::Testset::get_testset($si->{contest_id}, $si->{problem_id})} = undef;
    $t->param(run_details => [
        map {
            exists $run_details{$_} ? $run_details{$_} :
            $contest->{show_all_tests} ?
                { test_rank => $_, (exists $testset{$_} ? 'not_processed' : 'not_in_testset') => 1 } :
            () 
        } (1..$last_test)
    ]);
}


sub prepare_source
{
    my ($show_msg) = @_;
    my $rid = url_param('rid') or return;

    my $sources_info = get_sources_info(request_id => $rid, get_source => 1)
        or return;

    my $is_jury = is_jury_in_contest(contest_id => $sources_info->{contest_id});
    $is_jury || $sources_info->{account_id} == ($uid || 0)
        or return ($show_msg && msg(126));
    my $se = param('src_enc');
    if ($se && source_encodings()->{$se})
    {
        Encode::from_to($sources_info->{src}, $se, 'utf-8');
    }
    ($sources_info, $is_jury);
}


sub view_source_frame
{
    init_template('main_view_source.htm');
    my ($sources_info, $is_jury) = prepare_source(1);
    $sources_info or return;
    if ($is_jury && (my $file = param('replace_source')))
    {
        my $src = upload_source($file) or return;
        my $s = $dbh->prepare(q~
            UPDATE sources SET src = ? WHERE req_id = ?~);
        $s->bind_param(1, $src, { ora_type => 113 } ); # blob
        $s->bind_param(2, $sources_info->{req_id} );
        $s->execute;
        $dbh->commit;
        $sources_info->{src} = $src;
    }
    source_links($sources_info, $is_jury);
    $t->param(sources_info => [$sources_info]);
}


sub download_source_frame
{
    my ($si, $is_jury) = prepare_source(0);
    unless ($si)
    {
        init_template('main_view_source.htm');
        return;
    }

    $si->{file_name} =~ m/\.([^.]+)$/;
    my $ext = $1 || 'unknown';
    binmode(STDOUT, ':raw');
    print STDOUT CGI::header(
        -type => 'text/plain',
        -content_disposition => "inline;filename=$si->{req_id}.$ext");
    print STDOUT $si->{src};
}


sub run_log_frame
{
    init_template('main_run_log.htm');
    my $rid = url_param('rid') or return;

    # HACK: Чтобы избежать лишнего обращения к БД, требуем, чтобы
    # пользователь являлся членом жюри не только соревнования,
    # в котором просматривает задачу, но и своего текущего соревнования.
    $is_jury or return; 

    my $si = get_sources_info(request_id => $rid)
        or return;
    is_jury_in_contest(contest_id => $si->{contest_id})
        or return;

    $t->param(sources_info => [$si]);

    if (defined param 'set_state')
    {
        my $state = 
        {       
            not_processed =>         $cats::st_not_processed,
            accepted =>              $cats::st_accepted,
            wrong_answer =>          $cats::st_wrong_answer,
            presentation_error =>    $cats::st_presentation_error,
            time_limit_exceeded =>   $cats::st_time_limit_exceeded,
            memory_limit_exceeded => $cats::st_memory_limit_exceeded,            
            runtime_error =>         $cats::st_runtime_error,
            compilation_error =>     $cats::st_compilation_error,
            security_violation =>    $cats::st_security_violation,
            ignore_submit =>         $cats::st_ignore_submit,
        } -> {param('state')};

        my $failed_test = sprintf '%d', param('failed_test') || '0';
        enforce_request_state(
            request_id => $rid, failed_test => $failed_test, state => $state);
        my %st = state_to_display($state);
        while (my ($k, $v) = each %st)
        {
            $si->{$k} = $v;
        }
        $si->{failed_test} = $failed_test;
    }

    source_links($si, 1);

    my ($dump) =
        $dbh->selectrow_array(qq~SELECT dump FROM log_dumps WHERE req_id = ?~, {}, $rid);
    if ($dump) {
        $t->param(
            judge_log_dump_avalaible => 1,
            judge_log_dump => Encode::decode('CP1251', $dump)
        );
    }

    my $tests = $dbh->selectcol_arrayref(qq~
        SELECT rank FROM tests WHERE problem_id = ? ORDER BY rank~, {},
        $si->{problem_id});
    $t->param(tests => [ map {test_index => $_}, @$tests ]);
}


sub diff_runs_frame
{
    init_template('main_diff_runs.htm');
    $is_jury or return;
    
    my $si = get_sources_info(
        request_id => [ param('r1'), param('r2') ],
        get_source => 1
    ) or return;
    @$si == 2 or return;

    # Пользователь должен входить в жюри турниров, которым принадлежат обе задачи.
    # Если задачи принадлежат одному и тому же турниру, проверяем его только однажды.
    my ($cid1, $cid2) = map $_->{contest_id}, @$si;
    is_jury_in_contest(contest_id => $cid1)
        or return;
    $cid1 == $cid2 || is_jury_in_contest(contest_id => $cid2)
        or return;

    source_links($_, 1) for @$si;
    
    for my $info (@$si)
    {
        $info->{lines} = [split "\n", $info->{src}];
        s/\s*$// for @{$info->{lines}};
    }
    
    my @diff = ();

    my $SL = sub { $si->[$_[0]]->{lines}->[$_[1]] || '' }; 
    
    my $match = sub { push @diff, escape_html($SL->(0, $_[0])) . "\n"; };
    my $only_a = sub { push @diff, span({class=>'diff_only_a'}, escape_html($SL->(0, $_[0])) . "\n"); };
    my $only_b = sub { push @diff, span({class=>'diff_only_b'}, escape_html($SL->(1, $_[1])) . "\n"); };

    Algorithm::Diff::traverse_sequences(
        $si->[0]->{lines},
        $si->[1]->{lines},
        {
            MATCH     => $match,     # callback on identical lines
            DISCARD_A => $only_a,    # callback on A-only
            DISCARD_B => $only_b,    # callback on B-only
        }
    );

    $t->param(
        sources_info => $si,
        diff_lines => [map {line => $_}, @diff]
    );
}


sub cache_req_points
{
    my ($req_id) = @_;
    my $points = $dbh->selectall_arrayref(qq~
        SELECT RD.result, T.points
            FROM reqs R
            INNER JOIN req_details RD ON RD.req_id = R.id
            INNER JOIN tests T ON RD.test_rank = T.rank AND T.problem_id = R.problem_id
        WHERE R.id = ?~, { Slice => {} },
        $req_id
    );

    my $total = 0;
    for (@$points)
    {
        $total += $_->{result} == $cats::st_accepted ? max($_->{points} || 0, 0) : 0;
    }

    $dbh->do(q~UPDATE reqs SET points = ? WHERE id = ?~, undef, $total, $req_id);
    $total;
}


sub rank_get_results
{
    my ($frozen, $contest_list, $cond_str, $max_cached_req_id) = @_;
    my @conditions = ();
    my @params = ();
    if ($frozen && !$is_jury)
    {
        if ($is_team)
        {
            push @conditions, '(R.submit_time < C.freeze_date OR R.account_id = ?)';
            push @params, $uid;
        }
        else
        {
            push @conditions, 'R.submit_time < C.freeze_date';
        }
    }
    if ($is_team && !$is_jury && $virtual_diff_time)
    {
        push @conditions, "(R.submit_time - CA.diff_time < CATS_SYSDATE() - $virtual_diff_time)";
    }

    $cond_str .= join '', map " AND $_", @conditions;

    $dbh->selectall_arrayref(qq~
        SELECT
            R.id, R.state, R.problem_id, R.account_id, R.points,
            ((R.submit_time - C.start_date - CA.diff_time) * 1440) AS time_elapsed
        FROM reqs R, contests C, contest_accounts CA, contest_problems CP
        WHERE
            CA.contest_id = C.id AND CA.account_id = R.account_id AND R.contest_id = C.id AND
            CP.problem_id = R.problem_id AND CP.contest_id = C.id AND
            CA.is_hidden = 0 AND CP.status < ? AND R.state >= ? AND R.id > ? AND
            C.id IN ($contest_list)$cond_str
        ORDER BY R.id~, { Slice => {} },
        $cats::problem_st_hidden, $cats::request_processed, $max_cached_req_id, @params
    );
}


sub get_contest_list_param
{
    my $contest_list = url_param('clist') || $cid;
    # sanitize
    join(',', grep { $_ > 0 } map { sprintf '%d', $_ } split ',', $contest_list) || $cid;
}


sub rank_table
{
    my $template_name = shift;
    init_template('main_rank_table_content.htm');
    $t->param(printable => url_param('printable'));

    my $hide_ooc = url_param('hide_ooc') || '0';
    $hide_ooc =~ /^[01]$/
        or $hide_ooc = 0;

    my $hide_virtual = url_param('hide_virtual') || '0';
    $hide_virtual =~ /^[01]$/
        or $hide_virtual = (!$is_virtual && !$is_jury || !$is_team);
        

    my $contest_list = get_contest_list_param;
    my (undef, $frozen, $not_started, $default_show_points) = get_contests_info($contest_list, $uid);
    my $show_points = url_param('points');
    defined $show_points or $show_points = $default_show_points;
    my $use_cache = url_param('cache');
    # по умолчанию кешируем внешние ссылки
    $use_cache = 1 if !defined $use_cache && !defined $uid;
    
    my @p = ('rank_table', clist => $contest_list, cache => $use_cache);
    $t->param(
        not_started => $not_started && !$is_jury,
        frozen => $frozen,
        hide_ooc => !$hide_ooc,
        hide_virtual => !$hide_virtual,
        href_hide_ooc => url_f(@p, hide_ooc => 1, hide_virtual => $hide_virtual),
        href_show_ooc => url_f(@p, hide_ooc => 0, hide_virtual => $hide_virtual),
        href_hide_virtual => url_f(@p, hide_virtual => 1, hide_ooc => $hide_ooc),
        href_show_virtual => url_f(@p, hide_virtual => 0, hide_ooc => $hide_ooc),
        show_points => $show_points,
    );
    #return if $not_started;

    my @p_id = CATS::RankTable::get_problem_ids($contest_list, $show_points);
    my $virtual_cond = $hide_virtual ? ' AND (CA.is_virtual = 0 OR CA.is_virtual IS NULL)' : '';
    my $ooc_cond = $hide_ooc ? ' AND CA.is_ooc = 0' : '';

    my $cache_file = cats_dir() . "./rank_cache/$contest_list#$hide_ooc#$hide_virtual#";

    my %init_problem = (runs => 0, time_consumed => 0, solved => 0, points => undef);
    my $select_teams = sub
    {
        my ($account_id) = @_;
        my $acc_cond = $account_id ? 'AND A.id = ?' : '';
        my $res = $dbh->selectall_hashref(qq~
            SELECT
                A.team_name, A.motto, A.country,
                MAX(CA.is_virtual) AS is_virtual, MAX(CA.is_ooc) AS is_ooc, MAX(CA.is_remote) AS is_remote,
                CA.account_id
            FROM accounts A, contest_accounts CA
            WHERE CA.contest_id IN ($contest_list) AND A.id = CA.account_id AND CA.is_hidden = 0
                $virtual_cond $ooc_cond $acc_cond
            GROUP BY CA.account_id, A.team_name, A.motto, A.country~, 'account_id', { Slice => {} },
            ($account_id || ())
        );

        for my $team (values %$res)
        {
            # поскольку виртуальный участник всегда ooc, не выводим лишнюю строчку
            $team->{is_ooc} = 0 if $team->{is_virtual};
            $team->{$_} = 0 for qw(total_solved total_runs total_time total_points);
            ($team->{country}, $team->{flag}) = get_flag($_->{country});
            $team->{problems} = { map { $_ => { %init_problem } } @p_id };
        }

        $res;
    };

    my ($teams, $problems, $max_cached_req_id) = ({}, {}, 0);
    if ($use_cache && !$is_virtual && -f $cache_file &&
        (my $cache = Storable::lock_retrieve($cache_file)))
    {
        ($teams, $problems, $max_cached_req_id) = @{$cache}{qw(t p r)};
        # Если добавилась задача, проинициализируем её данные
        for my $p (@p_id)
        {
            next if $problems->{$p};
            $problems->{$p} = { total_runs => 0, total_accepted => 0, total_points => 0 };
            $_->{problems}->{$p} = { %init_problem } for values %$teams;
        }
    }
    else
    {
        $problems =
            { map { $_ => {total_runs => 0, total_accepted => 0, total_points => 0} } @p_id };
        $teams = $select_teams->();
    }

    my $results = rank_get_results($frozen, $contest_list, $virtual_cond . $ooc_cond, $max_cached_req_id);
    my ($need_commit, $max_req_id) = (0, 0);
    for (@$results)
    {
        $max_req_id = $_->{id} if $_->{id} > $max_req_id;
        $_->{time_elapsed} ||= 0;
        next if $_->{state} == $cats::st_ignore_submit;
        my $t = $teams->{$_->{account_id}} || $select_teams->($_->{account_id});
        my $p = $t->{problems}->{$_->{problem_id}};
        if ($show_points && !defined $_->{points})
        {
            $_->{points} = cache_req_points($_->{id});
            $need_commit = 1;
        }
        next if $p->{solved} && !$show_points;

        if ($_->{state} == $cats::st_accepted)
        {
            my $te = int($_->{time_elapsed} + 0.5);
            $p->{time_consumed} = $te + $p->{runs} * $cats::penalty;
            $p->{time_hm} = sprintf('%d:%02d', int($te / 60), $te % 60);
            $p->{solved} = 1;
            $t->{total_time} += $p->{time_consumed};
            $t->{total_solved}++;
            $problems->{$_->{problem_id}}->{total_accepted}++;
        }
        if ($_->{state} != $cats::st_security_violation) 
        {
            $problems->{$_->{problem_id}}->{total_runs}++;
            $p->{runs}++;
            $t->{total_runs}++;
            $p->{points} ||= 0;
            my $dp = ($_->{points} || 0) - $p->{points};
            $t->{total_points} += $dp;
            $problems->{$_->{problem_id}}->{total_points} += $dp;
            $p->{points} = $_->{points};
        }
    }

    $dbh->commit if $need_commit;
    if (!$frozen && !$is_virtual && @$results && !$contest->is_practice)
    {
        Storable::lock_store({ t => $teams, p => $problems, r => $max_req_id }, $cache_file);
    }

    my $sort_criteria = $show_points ?
        sub {
            $b->{total_points} <=> $a->{total_points} ||
            $b->{total_runs} <=> $a->{total_runs} 
        }:
        sub {
            $b->{total_solved} <=> $a->{total_solved} ||
            $a->{total_time} <=> $b->{total_time} ||
            $b->{total_runs} <=> $a->{total_runs}
        };
    my @rank = sort $sort_criteria values %$teams;

    my ($row_num, $same_place_count, $row_color) = (1, 0, 0);
    my %prev = ('time' => 1000000, solved => -1, points => -1);

    for my $team (@rank)
    {
        my @columns = ();

        for (@p_id)
        {
            my $p = $team->{problems}->{$_};

            my $c = $p->{solved} ? '+' . ($p->{runs} - 1 || '') : -$p->{runs} || '.';

            push @columns, {
                td => $c, 'time' => ($p->{time_hm} || ''),
                points => (defined $p->{points} ? $p->{points} : '.')
            };
        }

        $row_color = 1 - $row_color
            if $show_points ? $row_num % 5 == 1 : $prev{solved} > $team->{total_solved};
        if ($show_points ?
                $prev{points} > $team->{total_points}:
                $prev{solved} > $team->{total_solved} || $prev{'time'} < $team->{total_time})
        {
            $same_place_count = 1;
        }
        else
        {
            $same_place_count++;
        }

        $prev{$_} = $team->{"total_$_"} for keys %prev;

        $team->{row_color} = $row_color;
        $team->{contestant_number} = $row_num++;
        $team->{place} = $row_num - $same_place_count;
        $team->{columns} = [ @columns ];
        $team->{show_points} = $show_points;
        $team->{href_console} = url_f('console', uf => $team->{account_id});
    }

    $t->param(
        problem_colunm_width => (
            @p_id <= 6 ? 6 :
            @p_id <= 8 ? 5 :
            @p_id <= 10 ? 4 :
            @p_id <= 20 ? 3 : 2 ),
        problem_stats => [
            map {{
                %{$problems->{$_}},
                percent_accepted => int(
                    $problems->{$_}->{total_accepted} /
                    ($problems->{$_}->{total_runs} || 1) * 100 + 0.5),
                average_points => sprintf('%.1f', $problems->{$_}->{total_points} / $row_num)
            }} @p_id 
        ],
        problem_stats_color => 1 - $row_color,
        rank => [ @rank ]
    );

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
    init_template('main_rank_table.htm');

    my $contest_list = get_contest_list_param;
    ($contest->{title}) = get_contests_info($contest_list, $uid);

    my @params = (
        hide_ooc => $hide_ooc, hide_virtual => $hide_virtual, cache => $cache,
        clist => $contest_list, points => $show_points
    );
    $t->param(href_rank_table_content => url_f('rank_table_content', @params));
    my $submenu =
        [ { href_item => url_f('rank_table_content', @params, printable => 1), item_name => res_str(552) } ];
    if ($is_jury)
    {
        push @$submenu,
            { href_item => url_f('rank_table', @params, cache => 1 - ($cache || 0)), item_name => res_str(553) },
            { href_item => url_f('rank_table', @params, points => 1 - ($show_points || 0)), item_name => res_str(554) };
    }
    $t->param(submenu => $submenu);
}


sub rank_table_content_frame
{
    rank_table('main_rank_table_iframe.htm');  
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


sub check_spelling
{
    my ($word) = @_;
    return $word if $word =~ /\d/;
    my $koi = Encode::encode('KOI8-R', $word);
    {
        no encoding;
        $koi =~ s/ё/е/g;
        use encoding 'utf8', STDIN => undef;
    }
    return $word if $spellchecker->check($koi);
    my $suggestion = join ' | ', grep $_, (map russian($_), $spellchecker->suggest($koi))[0..9];
    return qq~<a class="spell" title="$suggestion">$word</a>~;
}


sub process_text
{
    if ($spellchecker)
    {
        my @tex_parts = split /\$/, $text_span;
        my $i = 1;
        for (@tex_parts)
        {
            $i = !$i;
            next if $i;
            # игнорировать entities, учитывать апострофы как часть слов, первый символ должен быть буквой
            s/(?<!(?:\w|&))(\w(?:\w|\')*)/check_spelling($1)/eg;
        }
        $html_code .= join '$', @tex_parts;
        # split игнорирует разделитель в конце строки, m// игнорирует \n в конце строки, поэтому \z
        $html_code .= '$' if $text_span =~ /\$\z/s;
    }
    else
    {
        $html_code .= $text_span;
    }
    $text_span = '';
}


# генерация страницы с текстом задач
sub start_element
{
    my ($el, %atts) = @_;

    process_text;
    $html_code .= "<$el";
    for my $name (keys %atts)
    {
        my $attrib = $atts{$name};
        $html_code .= qq~ $name="$attrib"~;
    }
    $html_code .= '>';
}


sub end_element
{
    my ($el) = @_;
    process_text;
    $html_code .= "</$el>";
}


sub ch_1
{
    my ($p, $text) = @_;
    # Склеиваем подряд идущие текстовые элементы, и потом обрабатываем их все вместе
    $text_span .= $text;
}


# если задача ещё ни разу не скачивалась, сгенерировать для неё хеш
sub ensure_problem_hash
{
    my ($problem_id, $hash) = @_;
    return 1 if $$hash;
    my @ch = ('a'..'z', 'A'..'Z', '0'..'9');
    $$hash = join '', map @ch[rand @ch], 1..32;
    #$$hash = mktemp('X' x 32);
    $dbh->do(qq~UPDATE problems SET hash = ? WHERE id = ?~, undef, $$hash, $problem_id);
    $dbh->commit;
    return 0;
}


sub download_image
{
    my ($name) = @_;
    # полагаем, что картинки относительно маленькие (единицы Кб), поэтому эффективнее
    # вытаскивать их одним запросом вместе с хешем задачи
    my ($pic, $ext, $hash) = $dbh->selectrow_array(qq~
        SELECT c.pic, c.extension, p.hash FROM pictures c
        INNER JOIN problems p ON c.problem_id = p.id
        WHERE p.id = ? AND c.name = ?~, {}, $current_pid, $name);
    ensure_problem_hash($current_pid, \$hash);
    return 'unknown' if !$name;
    $ext ||= '';
    # секьюрити. это может привести к дублированию картинок, например, с именами pic1 и pic.1
    $name =~ tr/a-zA-Z0-9_//cd;
    $ext =~ tr/a-zA-Z0-9_//cd;
    my $fname = "./download/img/img_${hash}_$name.$ext";
    -f cats_dir() . $fname or CATS::BinaryFile::save(cats_dir() . $fname, $pic);
    return $fname;
}


sub sh_1
{
    my ($p, $el, %atts) = @_;
    
    if ($el eq 'img' && $atts{'picture'})
    {
        $atts{src} = download_image($atts{'picture'});
        delete $atts{picture};
    }
    start_element($el, %atts);
}


sub eh_1
{
    my ($p, $el) = @_;
    end_element($el);
}


sub parse
{
    my $xml_patch = shift;
    my $parser = new XML::Parser::Expat;

    $html_code = '';

    $parser->setHandlers(
        'Start' => \&sh_1,
        'End'   => \&eh_1,
        'Char'  => \&ch_1);

    $parser->parse("<p>$xml_patch</p>");
    return $html_code;
}


sub contest_visible
{
    return (1, 1) if $is_jury;

    my $pid = url_param('pid');
    my $cpid = url_param('cpid');

    my ($s, $t, $p) = ('', '', '');
    if (defined $pid)
    {
        $s = 'INNER JOIN problems P ON C.id = P.contest_id';
        $t = 'P';
        $p = $pid;
    }
    elsif (defined $cpid)
    {
        $s = 'INNER JOIN contest_problems CP ON C.id = CP.contest_id';
        $t = 'CP';
        $p = $cpid;
    }
    elsif (defined $cid) # Показать все задачи турнира.
    {
        $s = '';
        $t = 'C';
        $p = $cid;
    }    

    my ($since_start, $local_only, $orig_cid, $show_packages) = $dbh->selectrow_array(qq~
        SELECT CATS_SYSDATE() - C.start_date, C.local_only, C.id, C.show_packages
            FROM contests C $s WHERE $t.id = ?~,
        {}, $p);
    if ($since_start > 0)
    {
        $local_only or return (1, $show_packages);
        defined $uid or return (0, 0);
        # Должно быть локальное участие в основном турнире задачи
        # либо, если запрошены все задачи турнира, то в этом турнире.
        # Более полная проверка приводит к сложным условиям в составных турнирах.
        my ($is_remote) = $dbh->selectrow_array(q~
            SELECT is_remote FROM contest_accounts
            WHERE account_id = ? AND contest_id = ?~, {},
            $uid, $orig_cid);
        return (1, $show_packages) if defined $is_remote && $is_remote == 0;
    }
    return (0, 0);
}    


sub problem_text_frame
{
    my ($show, $explain) = contest_visible();
    if (!$show)
    {
        init_template('main_access_denied.htm');
        return;
    }
    $explain = $explain && url_param('explain');

    init_template('main_problem_text.htm');

    my (@id_problems, @problems, %pcodes);
    
    my $pid = url_param('pid');
    my $cpid = url_param('cpid');
    my $show_points;

    if (defined $pid)
    {
        push @id_problems, $pid;
    }
    elsif (defined $cpid)
    {
        (my $problem_id, my $code, $show_points) = $dbh->selectrow_array(qq~
            SELECT CP.problem_id, CP.code, C.rules
            FROM contests C INNER JOIN contest_problems CP ON CP.contest_id = C.id
            WHERE CP.id = ?~, {},
            $cpid) or return;
        push @id_problems, $problem_id;
        $pcodes{$problem_id} = $code;
    }
    else # Показать все задачи турнира
    {
        ($show_points) = $contest->{rules};

        # Надо либо делать проверку на статическую страницу,
        # либо не выводить скрытые задачи даже жюри.
        my $c = $dbh->prepare(qq~
            SELECT problem_id, code FROM contest_problems
            WHERE contest_id=? AND status < $cats::problem_st_hidden
            ORDER BY code~);
        $c->execute($cid);
        while (my ($problem_id, $code) = $c->fetchrow_array)
        {
            push @id_problems, $problem_id;
            $pcodes{$problem_id} = $code;
        }
    }
    
    my $use_spellchecker = $is_jury && !param('nospell');

    my $need_commit = 0;
    for my $problem_id (@id_problems)
    {
        $current_pid = $problem_id;
        
        my $problem_data = $dbh->selectrow_hashref(qq~
            SELECT
                id, contest_id, title, lang, time_limit, memory_limit,
                difficulty, author, input_file, output_file,
                statement, pconstraints, input_format, output_format, explanation,
                max_points
            FROM problems WHERE id = ?~, { Slice => {} },
            $problem_id);
        my $lang = $problem_data->{lang};

        if ($is_jury && !param('nokw'))
        {
            my $lang_col = $lang eq 'ru' ? 'name_ru' : 'name_en';
            my $kw_list = $dbh->selectcol_arrayref(qq~
                SELECT $lang_col FROM keywords K
                    INNER JOIN problem_keywords PK ON PK.keyword_id = K.id
                    WHERE PK.problem_id = ?
                    ORDER BY 1~, undef, $problem_id);
            $problem_data->{keywords} = join ', ', @$kw_list;
        }
        if ($use_spellchecker)
        {
            # Судя по документации Text::Aspell, опции нельзя менять для существующего
            # экземпляра класса, поэтому создаём каждый раз новый экземпляр.
            $spellchecker = Text::Aspell->new;
            $spellchecker->set_option('lang', $lang eq 'ru' ? 'ru_RU' : 'en_US');
        }
        else
        {
            undef $spellchecker;
        }

        if ($show_points && !$problem_data->{max_points})
        {
            $problem_data->{max_points} = CATS::RankTable::cache_max_points($problem_data->{id});
            $need_commit = 1;
        }

        $problem_data->{samples} = $dbh->selectall_arrayref(qq~
            SELECT rank, in_file, out_file
            FROM samples WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
            $problem_id);

        for my $field_name qw(statement pconstraints input_format output_format explanation)
        {
            for ($problem_data->{$field_name})
            {
                defined $_ or next;
                $text_span = '';
                $_ = $_ eq '' ? undef : Encode::encode_utf8(parse($_));
                CATS::TeX::Lite::convert_all($_);
                s/(?<=\s)-{2,3}/&#151;/g; # тире
            }
        }
        $explain or undef $problem_data->{explanation};
        push @problems, {
            %$problem_data,
            code => $pcodes{$problem_id},
            lang_ru => $lang eq 'ru',
            lang_en => $lang eq 'en',
            show_points => $show_points,
        };
    }
    $dbh->commit if $need_commit;

    $t->param(
        problems => [ @problems ],
        tex_styles => CATS::TeX::Lite::styles()
        #CATS::TeX::HTMLGen::gen_styles_html()
    );
}


sub envelope_frame
{
    init_template('main_envelope.htm');
    
    my $rid = url_param('rid') or return;

    my ($submit_time, $test_time, $state, $failed_test, $team_name, $contest_title) = $dbh->selectrow_array(qq~
        SELECT CATS_DATE(R.submit_time), CATS_DATE(R.test_time), R.state, R.failed_test, A.team_name, C.title
            FROM reqs R, contests C, accounts A
            WHERE R.id=? AND A.id=R.account_id AND C.id=R.contest_id~, {}, $rid);
    $t->param(
        submit_time => $submit_time,
        test_time => $test_time,
        team_name => $team_name,
        contest_title => $contest_title,
        failed_test_index => $failed_test,
        state_to_display($state)
    );
}


sub about_frame
{
    init_template('main_about.htm');
    my $problem_count = $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM problems P INNER JOIN contests C ON C.id = P.contest_id
        WHERE C.is_hidden = 0 OR C.is_hidden IS NULL~);
    $t->param(problem_count => $problem_count);
}


sub authors_frame
{
    init_template('main_authors.htm');
}


sub cmp_output_problem
{
    (cookie('limit') eq 'none')?
        init_template('main_cmp_out.htm'):
        init_template("main_cmp_limited.htm");


    my @submenu = ( { href_item => url_f('cmp', setparams => 1), item_name => res_str(546)} );
    $t->param(submenu => [ @submenu ] );    

# если не выбрана задача
    my $problem_id = param("problem_id");
    if (! defined ($problem_id))
    {
        #$t->param(noproblems => 1);
        return;
    }

# узнаем название задачи и кладём его в заголовок странички
    $t->param(problem_title => field_by_id($problem_id, 'PROBLEMS', 'title'));
    
# отправляем запрос

# читаем кукисы и в зависимости от них ставим дополнительные условия
  
    my $cont = (CGI::cookie('contest') or url_param('cid'));
    my $query = generate_cmp_query ($cont, cookie ('teams'), cookie ('versions'));
    my $c = $dbh->prepare ($query.order_by);
    $c->execute($problem_id);   
        
    my ($tname, $tid, $rid) = $c->fetchrow_array;
        
# если на запроc ничего не найдено
    if (! defined($tname))
    {
        $t->param(norecords => 1);
        return;
    }

# формирование заголовков таблицы
    my @titles;         #здесь хранить заголовки таблицы
    my %reqid;
    while ($tname)
    {
        my $stime = field_by_id($rid, 'reqs', 'CATS_DATE(result_time)');
        $stime =~ s/\s+$//;
        my %col_title = (id => $tname,
                         tid => $tid, submit_time => $stime,
                         rid => $rid, href => url_f('cmp', tid=>$tid, pid=>$problem_id));
        if (cookie('teams') eq 'all')
        {
            my $query = 'SELECT is_ooc, is_remote FROM contest_accounts WHERE account_id=?';
            (defined (CGI::cookie('contest'))) and $query .= ' AND contest_id=?';
            my $cc = $dbh->prepare($query);
                $cc->execute($tid, CGI::cookie('contest'));
            my ($is_ooc, $is_remote) = $cc->fetchrow_array;
            $cc->finish;
            $is_ooc and %col_title = (%col_title, ooc=>1);
            $is_remote and %col_title = (%col_title, remote=>1);
        }
        push @titles, \%col_title;
        #%reqid = (%reqid, $tid => $rid);
        ($tname, $tid, $rid) = $c->fetchrow_array;
    }
    $c->finish; 

    my %srcfiles;
    $dbh->{LongReadLen} = 16384;        ### 16Kb BLOB-поле
    foreach (@titles)
    {   
        $c = $dbh->prepare(q~
            SELECT
                S.src
            FROM
                SOURCES S
            WHERE
                S.req_id = ?
                        ~);
        $c->execute($$_{rid});
        my $src = $c->fetchrow_array;

        $srcfiles{$$_{rid}} = CATS::Diff::prepare_src ($src); # вот тут надо что-то менять

        #$reqid{$$_{tid}} = $rid;
        $c->finish;
    }

# создаем собственно табличку
    $t->param(col_titles => \@titles);
    my @rows = generate_table (\@titles, \%srcfiles, $problem_id, (cookie('limit') eq 'none')? 0:cookie('limit'));
    $t->param(row => \@rows);
    1;  
}

sub cmp_output_team
{
    init_template('main_cmp_out.htm');

    my @submenu = ( { href_item => url_f('cmp', setparams => 1), item_name => res_str(546)} );
    $t->param(submenu => [ @submenu ] );    

    $t->param(team_stat => 1);

# узнаем название задачи и кладём его в заголовок странички
    $t->param(problem_title => field_by_id(param("pid"), 'PROBLEMS', 'title'));
# узнаем название команды и кладём его тоже в заголовок странички
    $t->param(team_name => field_by_id(param("tid"), 'ACCOUNTS', 'team_name'));

    $dbh->{LongReadLen} = 16384;        ### 16Kb BLOB-ОНКЪ
    my $c = $dbh->prepare(q~
        SELECT
            S.src,
            CATS_DATE(R.submit_time),
            R.id
        FROM
            SOURCES S,
            REQS R
        WHERE
            R.account_id = ? AND
            R.problem_id = ? AND
            S.req_id = R.id AND
            R.state <> ~.$cats::st_compilation_error);
    $c->execute(param("tid"), param("pid"));
    my ($src, $stime, $rid) = $c->fetchrow_array;
    my @titles;
    my %srcfiles;
    my %reqid;
    while ($stime)
    {
        my %col_title = (id => $stime, rid => $rid);
        push @titles, \%col_title;
        $srcfiles{$rid} = CATS::Diff::prepare_src ($src, cookie('algorythm'));
        ($src, $stime, $rid) = $c->fetchrow_array;
    }

    my @rows = generate_table (\@titles, \%srcfiles, param('pid'));
    $t->param(row => \@rows);
    $t->param(col_titles => \@titles);
   
    1;
}

sub cmp_show_sources
{
    init_template("main_cmp_source.htm");


    #$t->param(diff_href => url_f('diff_runs', r1 =>param('rid1'), r2 =>param('rid2')) );
    my @submenu = (
        { href_item => url_f('cmp', setparams => 1), item_name => res_str(546)},
        { href_item => url_f('diff_runs', r1 =>param('rid1'), r2 =>param('rid2')), item_name => res_str(547)}
        );
    $t->param(submenu => [ @submenu ] );    
    
    $t->param(problem_title => field_by_id(param("pid"), 'PROBLEMS', 'title'));
    
    my $c = $dbh->prepare(q~
        SELECT
            A.team_name,
            S.src
        FROM
            ACCOUNTS A,
            SOURCES S,
            REQS R
        WHERE
            R.id = ? AND
            A.id = R.account_id AND
            S.req_id = R.id                
                          ~);

    my @teams_rid = (param("rid1"), param("rid2"));
    my @team;
    my @src;
    foreach (@teams_rid)
    {
        $c->execute($_);
        my ($tname, $tsrc) = $c->fetchrow_array;
        push @team, $tname;
        push @src, $tsrc;
        $c->finish;
    }
    
    $t->param(team1 => $team[0]);
    $t->param(team2 => $team[1]);
    $t->param(source1 => prepare_src_show($src[0]));
    $t->param(source2 => prepare_src_show($src[1]));
}

sub cmp_set_params
{
    my $backlink = shift;
    init_template("main_cmp_param.htm");
    $t->param(backlink => $backlink);
    
    # кукис для выбора команд
    my $cookie;
    $cookie = CGI::cookie('teams') or $cookie = 'incontest';
    $t->param('teams_'.$cookie => 1);
    $t->param('init_team' => $cookie);
    
    # кукис для выбора версий
    $cookie = CGI::cookie('versions') or $cookie = 'last';
    $t->param('view_'.$cookie => 1);
    $t->param('init_vers' => $cookie);
    
    # кукис для выбора контеста
    $cookie = CGI::cookie('contest') or $cookie = param('cid');
    $t->param(init_cont => $cookie);
    $t->param(cur_cid => param('cid'));
    my $c = $dbh->prepare(q~SELECT id, title FROM contests ORDER BY title ~);
    $c->execute;
    my ($cid, $title) = $c->fetchrow_array;
    my @contests;
    while ($cid)
    {
        my %rec = (cid=>$cid, title=>$title);
        $cid == $cookie and %rec = (%rec, sel=>1);
        push @contests, \%rec;
        ($cid, $title) = $c->fetchrow_array;
    }
    $t->param(contest_all=>1) if $cookie=='all';
    $t->param(contests => \@contests);

    # кукис для выбора алгоритма
    $cookie = CGI::cookie('algorythm') or $cookie = 'diff';
    $t->param(init_algorythm => $cookie);
    $t->param('algorythm_'.$cookie => 1);
    
    # кукис для определения фильтра
    $cookie = cookie('limit') or $cookie = 80; #$cats::default_limit;
    if ($cookie eq 'none')
    {
        #$t->param(limited=>0);
        $t->param(init_limit=>80);
    }
    else
    {
        $t->param(limited=>1);
        $t->param(init_limit => $cookie);
    }
    
    1;
}


sub cmp_limited_output
{
    init_template('main_cmp_limited.htm');

    my $problem_id = param("problem_id");

    my $cont = (CGI::cookie('contest') or url_param('cid'));
    my $query = generate_cmp_query ($cont, cookie ('teams'), cookie ('versions'));
    my $c = $dbh->prepare ($query.order_by);
    $c->execute($problem_id);   
        
    my ($tname, $tid, $rid) = $c->fetchrow_array;

    
    1;
}

sub cmp_frame
{
    if (defined param("showtable") & $is_jury)
    {
        cmp_output_problem;
        return;
    }
    
    if (defined param("tid") & $is_jury)
    {
        cmp_output_team;
        return;
    }
    
    if (defined param("rid1") & $is_jury)
    {
        cmp_show_sources;
        return;
    }
    
    if (defined param("setparams") & $is_jury)
    {
        cmp_set_params(url_f('cmp'));
        return;
    }

    init_listview_template( "problems$cid" . ($uid || ''), 'problems', 'main_cmp.htm' );
    
    my @cols = 
              ( { caption => res_str(602), order_by => '3', width => '50%' },
                { caption => res_str(603), order_by => '4', width => '30%' },
                { caption => res_str(636), order_by => '5', width => '20%' });

    define_columns(url_f('cmp'), 0, 0, [ @cols ]);
       
    my $c;
    my $cont = (cookie('contest') or param ('cid'));
    my $query = generate_count_query($cont, cookie('teams'), cookie('versions'), 1);
    $c = $dbh->prepare($query.order_by);
    $c->execute();

    my $fetch_record = sub($)
    {            
        if ( my( $pid, $problem_name, $cid, $contest_name, $count) = $_[0]->fetchrow_array)
        {       
            return ( 
                is_practice => $contest->is_practice,
                editable => $is_jury,
                is_team => $is_team || $contest->is_practice,
                problem_id => $pid,
                problem_name => $problem_name, 
                href_view_problem => url_f('problem_text', pid => $pid),
                contest_name => $contest_name,
                count => $count
            );
        }   

        return ();
    };
            
    attach_listview(url_f('cmp'), $fetch_record, $c);

    $c->finish;

    my @submenu = ( { href_item => url_f('cmp', setparams => 1), item_name => res_str(546)} );
    $t->param(submenu => [ @submenu ] );    
}


sub generate_menu
{
    my $logged_on = $sid ne '';
  
    my @left_menu = (
        { item => $logged_on ? res_str(503) : res_str(500), 
          href => $logged_on ? url_function('logout', sid => $sid) : url_f('login') },
        { item => res_str(502), href => url_f('contests') },
        { item => res_str(525), href => url_f('problems') },
        { item => res_str(526), href => url_f('users') },
        { item => res_str(510),
          href => url_f('console', $is_jury ? () : (uf => $uid || get_anonymous_uid())) },
    );   

    if ($is_jury)
    {
        push @left_menu, (
            { item => res_str(548), href => url_f('compilers') },
            #{ item => res_str(545), href => url_f('cmp') } 
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
        push @left_menu, (
            { item => res_str(529), href => url_f('rank_table', $is_jury ? () : (cache => 1, hide_virtual => !$is_virtual)) }
        );
    }

    my @right_menu = ();

    if ($is_team && (url_param('f') ne 'logout'))
    {
        @right_menu = ( { item => res_str(518), href => url_f('settings') } );
    }
    
    push @right_menu,
        (       
        { item => res_str(544), href => url_f('about') },
        { item => res_str(501), href => url_f('registration') } );

    attach_menu('left_menu', undef, [ @left_menu ]);
    attach_menu('right_menu', 'about', [ @right_menu ]) ;
    $t->param(url_authors => url_f('authors'));
}


sub interface_functions ()
{
    {
        login => \&login_frame,
        logout => \&logout_frame,
        registration => \&registration_frame,
        settings => \&settings_frame,
        contests => \&contests_frame,
        console_content => \&console_content_frame,
        console => \&console_frame,
        problems => \&problems_frame,
        problem_select_testsets => \&problem_select_testsets,
        users => \&users_frame,
        compilers => \&compilers_frame,
        judges => \&judges_frame,
        keywords => \&keywords_frame,
        answer_box => \&answer_box_frame,
        send_message_box => \&send_message_box_frame,
        
        run_log => \&run_log_frame,
        view_source => \&view_source_frame,
        download_source => \&download_source_frame,
        run_details => \&run_details_frame,
        diff_runs => \&diff_runs_frame,
        compare_tests => \&compare_tests_frame,
        
        rank_table_content => \&rank_table_content_frame,
        rank_table => \&rank_table_frame,
        rank_problem_details => \&rank_problem_details,
        problem_text => \&problem_text_frame,
        envelope => \&envelope_frame,
        about => \&about_frame,
        authors => \&authors_frame,
        static => \&static_frame,
        
        'cmp' => \&cmp_frame,
    }
}


sub accept_request                                               
{
    my $output_file = '';
    if ((url_param('f') || '') eq 'static')
    {
        $output_file = CATS::StaticPages::process_static()
            or return;
    }
    initialize;
    $CATS::Misc::init_time = Time::HiRes::tv_interval($CATS::Misc::request_start_time, [ Time::HiRes::gettimeofday ]);

    my $function_name = url_param('f') || '';
    my $fn = interface_functions()->{$function_name} || \&about_frame;
    $fn->();

    generate_menu if defined $t;
    generate_output($output_file);
}

         
$CATS::Misc::request_start_time = [ Time::HiRes::gettimeofday ];
CATS::DB::sql_connect;
$dbh->rollback; # на случай брошенной транзакции от предыдущего запроса

#while(CGI::Fast->new)
#{  
#    accept_request;    
#    exit if (-M $ENV{ SCRIPT_FILENAME } < 0); 
#}
#eval
    { accept_request; };

$dbh->rollback;
#sql_disconnect;

1;
