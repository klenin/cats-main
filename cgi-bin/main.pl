#!/usr/bin/perl
use strict;
use warnings;
no warnings 'redefine';

#use File::Temp;
use File::Temp qw/tempfile tmpnam/;
use Encode;
use encoding 'utf8';
#use CGI::Fast qw(:standard);
use CGI qw(:standard);
use CGI::Util qw(unescape escape);
#use FCGI;

use Algorithm::Diff;

use CATS::Constants;
use CATS::Misc qw(:all);
use CATS::Data qw(:all);
use CATS::IP;
use CATS::Problem;
use CATS::Diff;
use CATS::TeX::Lite;

use vars qw($html_code $current_pid);


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
    is_official show_packages
)}


sub contest_string_params()
{qw(
    contest_name start_date freeze_date finish_date open_date rules
)}


sub get_contest_html_params
{
    my $p = {};
    
    $p->{$_} = scalar param($_) for contest_string_params();
    $p->{$_} = (param($_) || '') eq 'on' for contest_checkbox_params();
    
    $p->{contest_name} ne '' && length $p->{contest_name} < 100
        or return msg(27);
    
    $p;
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
          show_test_resources, show_checker_comment, is_official, show_packages
        ) VALUES(
          ?, ?, CATS_TO_DATE(?), CATS_TO_DATE(?), CATS_TO_DATE(?), CATS_TO_DATE(?), ?,
          0,
          ?, ?, ?, ?, ?, ?, ?)~,
        {},
        $cid, @$p{contest_string_params()},
        @$p{contest_checkbox_params()}
    );

    # автоматически зарегистрировать всех администраторов как жюри
    my $root_accounts = $dbh->selectcol_arrayref(qq~
        SELECT id FROM accounts WHERE srole = ?~, undef, $cats::srole_root);
    for (@$root_accounts)
    {
        $dbh->do(qq~
            INSERT INTO contest_accounts (
              id, contest_id, account_id,
              is_jury, is_pop, is_hidden, is_ooc, is_remote
            ) VALUES (?,?,?,?,?,?,?,?)~,
            {},
            new_id, $cid, $_,
            1, 1, 1, 1, 1
        );
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
          is_official, show_packages, rules
        FROM contests WHERE id = ?~, { Slice => {} },
        $id
    );
    # Ask: наверное, на самом деле надо исправить CATS_DATE
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
          show_test_resources=?, show_checker_comment=?, is_official=?, show_packages=?
          WHERE id=?~,
        {},
        @$p{contest_string_params()},
        @$p{contest_checkbox_params()},
        $edit_cid
    );
    $dbh->commit;
    # если переименовали текущи турнир, сразу изменить заголовок окна
    if ($edit_cid == $cid) {
        $contest_title = $p->{contest_name};
    }
}


sub contest_online_registration
{
    !get_registered_contestant(contest_id => $cid)
        or return msg(111);

    my ($finished, $closed) = $dbh->selectrow_array(qq~
        SELECT CATS_SYSDATE() - finish_date, closed FROM contests WHERE id = ?~, {}, $cid);
        
    $finished <= 0
        or return msg(108);

    !$closed
        or return msg(105);

    $dbh->do(qq~
        INSERT INTO contest_accounts (
          id, contest_id,
          account_id, is_jury, is_pop, is_hidden, is_ooc, is_remote, is_virtual, diff_time
        ) VALUES (?,?,?,?,?,?,?,?,?,?)~, {},
          new_id, $cid, $uid, 0, 0, 0, 1, 1, 0, 0);
    $dbh->commit;
}


sub contest_virtual_registration
{
    my ($registered, $is_virtual) = get_registered_contestant(
         fields => '1, is_virtual', contest_id => $cid);
        
    !$registered || $is_virtual
        or return msg(114);

    my ($time_since_start, $time_since_finish, $closed, $is_official) = $dbh->selectrow_array(qq~
        SELECT CATS_SYSDATE() - start_date, CATS_SYSDATE() - finish_date, closed, is_official
          FROM contests WHERE id=?~, {},
        $cid);
        
    $time_since_start >= 0
        or return msg(109);
    
    $time_since_finish >= 0 || !$is_official
        or return msg(122);

    !$closed
        or return msg(105);

    # при повторной регистрации удаляем старые результаты
    if ($registered)
    {
        $dbh->do(qq~DELETE FROM reqs WHERE account_id = ? AND contest_id = ?~, {}, $uid, $cid);
        $dbh->do(qq~DELETE FROM contest_accounts WHERE account_id = ? AND contest_id = ?~, {}, $uid, $cid);
        $dbh->commit;
        msg(113);
    }

    $dbh->do(qq~
        INSERT INTO contest_accounts (
          id, contest_id, account_id, is_jury, is_pop, is_hidden, is_ooc, is_remote, is_virtual, diff_time
        ) VALUES (
          ?,?,?,?,?,?,?,?,?,?
        )~, {}, 
        new_id, $cid, $uid, 0, 0, 0, 1, 1, 1, $time_since_start
    );
    $dbh->commit;
}


sub contests_select_current
{
    defined $uid or return;

    my ($registered, $is_virtual, $is_jury) = get_registered_contestant(
      fields => '1, is_virtual, is_jury', contest_id => $cid
    );
    return if $is_jury;
    
    my ($title, $time_since_finish) = $dbh->selectrow_array(qq~
        SELECT title, CATS_SYSDATE() - finish_date FROM contests WHERE id = ?~, {},
        $cid);

    $t->param(selected_contest_title => $title);

    if ($time_since_finish > 0) {
        msg(115);
    }
    elsif (!$registered) {
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

sub authenticated_contests_view ()
{
    my $sth = $dbh->prepare(qq~
        SELECT id, title, CATS_DATE(start_date) AS start_date, CATS_DATE(finish_date) AS finish_date, 
          (SELECT COUNT(*) FROM contest_accounts WHERE contest_id=contests.id AND account_id=?) AS registered,
          (SELECT is_virtual FROM contest_accounts WHERE contest_id=contests.id AND account_id=?) AS is_virtual,
          (SELECT is_jury FROM contest_accounts WHERE contest_id=contests.id AND account_id=?) AS is_jury,
          closed, is_official, rules
        FROM contests ~.order_by);
    $sth->execute($uid, $uid, $uid);

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
    my $sth = $dbh->prepare(qq~
        SELECT id, title, closed, is_official, rules,
          CATS_DATE(start_date) AS start_date,
          CATS_DATE(finish_date) AS finish_date
          FROM contests ~.order_by
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
        { caption => res_str(601), order_by => 'ctype DESC, title',       width => '40%' },
        { caption => res_str(600), order_by => 'ctype DESC, start_date',  width => '20%' },
        { caption => res_str(631), order_by => 'ctype DESC, finish_date', width => '20%' },
        { caption => res_str(630), order_by => 'ctype DESC, closed',      width => '20%' } ]);

    attach_listview(url_f('contests'),
        defined $uid ? authenticated_contests_view : anonymous_contests_view);

    if ($is_root)
    {
        my @submenu = ( { href_item => url_f('contests', new => 1), item_name => res_str(537) } );
        $t->param(submenu => [ @submenu ] );
    }

    $t->param(
        authorized => defined $uid,
        href_contests => url_f('contests'),
        editable => $is_root
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
            map { {value => $_, text => $_ || russian('все'), selected => $v eq $_} } (1..5, 10, 0)
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
            CA.id~,
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
            CA.id~,
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
            CA.id
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
            CAST(NULL AS INTEGER)
            FROM messages M, dummy_table D
        ~,
    );

    my $my_events_only = url_param('my');
    for ($my_events_only)
    {
        $_ = '' if !defined $_;
        /[01]/ or $_ = !$is_jury;
    }
    my $events_filter = '';
    my @events_filter_params = ();
    if ($my_events_only)
    {
        $events_filter = 'AND A.id = ?';
        @events_filter_params = $uid ? ($uid) :
            $dbh->selectrow_array(qq~
                SELECT id FROM accounts WHERE login=?~, {}, $cats::anonymous_login);
    }

    my $c;
    if ($is_jury)
    {
        my $t = $is_root ? '' : ' C.id = ? AND';
        $c = $dbh->prepare(qq~
            SELECT
                $console_select{run}
                FROM reqs R, problems P, accounts A, contests C, contest_accounts CA, dummy_table D 
                WHERE (R.submit_time > CATS_SYSDATE() - $day_count) AND R.contest_id=C.id AND$t
                R.problem_id=P.id AND R.account_id=A.id AND CA.account_id=A.id AND CA.contest_id=R.contest_id
                $events_filter
            UNION
            SELECT
                $console_select{question}
                FROM questions Q, contest_accounts CA, dummy_table D, accounts A
                WHERE (Q.submit_time > CATS_SYSDATE() - $day_count) AND
                Q.account_id=CA.id AND A.id=CA.account_id
                $events_filter
            UNION
            SELECT
                $console_select{message}
                FROM messages M, contest_accounts CA, dummy_table D, accounts A
                WHERE (M.send_time > CATS_SYSDATE() - $day_count) AND
                M.account_id=CA.id AND A.id=CA.account_id
                $events_filter
	        UNION
            SELECT
                $console_select{broadcast}
                WHERE (M.send_time > CATS_SYSDATE() - $day_count) AND M.broadcast=1
            ORDER BY 2 DESC~);
        $c->execute(
            ($is_root ? () : $cid),
            @events_filter_params, @events_filter_params, @events_filter_params);
    }
    elsif ($is_team)
    {
        $c = $dbh->prepare(qq~
            SELECT
                $console_select{run}
                FROM reqs R, problems P, accounts A, contests C, dummy_table D, contest_accounts CA
                WHERE (R.submit_time > CATS_SYSDATE() - $day_count) AND
                    R.problem_id=P.id AND R.contest_id=C.id AND C.id=? AND R.account_id=A.id AND
                    CA.account_id=A.id AND CA.contest_id=C.id AND CA.is_hidden=0 AND
                    (A.id=? OR (R.submit_time < C.freeze_date OR CATS_SYSDATE() > C.defreeze_date))
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
            $team_id, $team_name, $country_abb, $last_ip, $caid
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
            $last_ip_short = $1;
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
        );
    };
            
    attach_listview(url_f('console'), $fetch_console_record, $c);
      
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
        my_events_only => $my_events_only,
        href_my_events_only => url_f('console', my => 1),
        href_all_events => url_f('console', my => 0),
    );
    my $s = $t->output;
    init_template($template_name);

    $t->param(
        console_content => $s,
        is_team => $is_team,
    );
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


sub console_frame
{        
    init_listview_template("console$cid" . ($uid || ''), 'console', 'main_console.htm');  
    init_console_listview_additionals;
    
    my $question_text = param('question_text');
    my $selection = param('selection');
   
    if (defined param('retest'))
    {
        if (retest_submissions($selection))
        {
            $selection = '';
        }
    }

    my $my_events_only = url_param('my');
    $t->param(
        href_console_content => url_f('console_content', my => $my_events_only),
        is_team => $is_team,
        is_jury => $is_jury,
        question_text => $question_text,
        selection => $selection,
        href_view_source => url_f('view_source'),
        href_run_details => url_f('run_details'),
        href_run_log => url_f('run_log'),
        href_diff => url_f('diff_runs'),
    );
    
    if (defined param('send_question'))
    {
        send_question_to_jury($question_text);
    }
}


sub console_content_frame
{
    console('main_console_iframe.htm');  
}


sub problems_change_status ()
{
    my $pid = param('problem_id')
      or return msg(54);
    
    my $new_status = param('status');
    exists problem_status_names()->{$new_status} or return;
    
    $dbh->do(qq~
        UPDATE contest_problems SET status = ?
            WHERE contest_id = ? AND problem_id = ?~, {},
        $new_status, $cid, $pid);
    $dbh->commit;
}


sub show_unused_problem_codes ()
{
    my $c = $dbh->selectcol_arrayref(qq~
        SELECT code FROM contest_problems WHERE contest_id = ?~, {},
        $cid
    );
    my %used_codes = ();
    @used_codes{@$c} = undef;
    
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


sub problems_new_save
{
    my $file = param('zip')
        or return msg(53);

    my ($fh, $fname) = tmpnam;
    my ($br, $buffer);
       
    while ($br = read($file, $buffer, 1024))
    {
        syswrite($fh, $buffer, $br);
    }
    close $fh;

    my $pid = new_id;
    my $problem_code = param('problem_code');
    
    my ($st, $import_log) = CATS::Problem::import_problem($fname, $cid, $pid, 0);
   
    $import_log = Encode::encode_utf8( escape_html($import_log) );  
    $t->param(problem_import_log => $import_log);

    $st ||= !$dbh->do(qq~
        INSERT INTO contest_problems(id, contest_id, problem_id, code, status)
            VALUES (?,?,?,?,0)~, {},
        new_id, $cid, $pid, $problem_code);

    (!$st) ? $dbh->commit : $dbh->rollback;
    if ($st) { msg(52); }
}


sub problems_link_frame
{
    init_listview_template('link_problem_' || ($uid || ''),
        'link_problem', 'main_problems_link.htm');

    show_unused_problem_codes;

    my $cols = [
        { caption => res_str(602), order_by => '2', width => '30%' }, 
        { caption => res_str(603), order_by => '3', width => '30%' },                    
        { caption => res_str(604), order_by => '4', width => '10%' },
        { caption => res_str(605), order_by => '5', width => '10%' },
        { caption => res_str(606), order_by => '6', width => '10%' },
    ];
    define_columns(url_f('problems', link => 1), 0, 0, $cols);
    
    my $security_check = $is_root ?
      {cond => '', 'params' => []} :
      {   
        cond => q~
          AND (
            EXISTS (
              SELECT 1 FROM contest_accounts WHERE contest_id = C.id AND account_id = ? AND is_jury = 1
            ) OR (CURRENT_TIMESTAMP > C.finish_date)
          )~,
        params => [$uid]
      };
      
    my $c = $dbh->prepare(qq~
        SELECT P.id, P.title, C.title, 
          (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_accepted), 
          (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_wrong_answer), 
          (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_time_limit_exceeded),
          (SELECT COUNT(*) FROM contest_problems CP WHERE CP.problem_id = P.id AND CP.contest_id=?)
        FROM problems P, contests C
        WHERE
          C.id=P.contest_id$security_check->{cond}
        ~.order_by);
    # interbase bug
    $c->execute(@{$security_check->{params}}, $cid);

    my $fetch_record = sub($)
    {            
        my (
            $pid, $problem_name, $contest_name, $accept_count, $wa_count, $tle_count, $linked
        ) = $_[0]->fetchrow_array
            or return ();
        return ( 
            linked => $linked,
            problem_id => $pid,
            problem_name => $problem_name, 
            href_view_problem => url_f('problem_text', pid => $pid),
            contest_name => $contest_name, 
            accept_count => $accept_count, 
            wa_count => $wa_count,
            tle_count => $tle_count,
        );
    };
            
    attach_listview(url_f('problems', link => 1), $fetch_record, $c);

    $t->param(practice => $is_practice, href_action => url_f('problems'));
    
    $c->finish;
}


sub problems_link_save
{       
    my $pid = param('problem_id')
        or return msg(104);

    my $problem_code = undef;
    if (!$is_practice)
    {
        $problem_code = param('problem_code') or return;
    }

    $dbh->do(qq~
        INSERT INTO contest_problems(id, contest_id, problem_id, code, status)
            VALUES (?,?,?,?,0)~, {},
        new_id, $cid, $pid, $problem_code);

    $dbh->commit;
}


sub problems_replace_direct
{
    my $pid = param('problem_id')
        or return msg(54);
   
    my $file = param('zip');
    $file =~ /\.(zip|ZIP)$/
        or return msg(53);

    my ($fh, $fname) = tmpnam;
    my ($br, $buffer);

    while ( $br = read( $file, $buffer, 1024 ) )
    {
        syswrite($fh, $buffer, $br);
    }
    close $fh;

    my ($contest_id) = $dbh->selectrow_array(qq~SELECT contest_id FROM problems WHERE id=?~, {}, $pid);
    if ($contest_id != $cid)
    {
      #$t->param(linked_problem => 1);
      msg(117);
      return;
    }
    my ($st, $import_log) = CATS::Problem::import_problem($fname, $cid, $pid, 1);
    $import_log = Encode::encode_utf8( escape_html($import_log) );  
    $t->param(problem_import_log => $import_log);

    $st ? $dbh->rollback : $dbh->commit;
    if ($st) { msg(52); }
}


sub download_problem
{
    $t = undef;

    my $download_dir = './download';

    my $pid = param('download');

    my ($fh, $fname) = tempfile( 
        'problem_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX', 
        DIR => $download_dir, SUFFIX => ".zip"  );

    my ($zip) = 
        $dbh->selectrow_array(qq~SELECT zip_archive FROM problems WHERE id=?~, {}, $pid);

    syswrite($fh, $zip, length($zip));    

    close $fh;
    
    print redirect(-uri=> "$fname");
}



sub get_source_de
{
     my $file_name = shift;

     my $c = $dbh->prepare(qq~SELECT id, code, description, file_ext FROM default_de WHERE in_contests=1 ORDER BY code~);
     $c->execute;
    
     my ( $vol, $dir, $fname, $name, $ext ) = split_fname( lc $file_name );

     while (my ($did, $code, $description, $file_ext) = $c->fetchrow_array)
     {
        my @ext_list = split(/\;/, $file_ext);
 
        foreach my $i (@ext_list)
        {
            if ($i ne '' && $i eq $ext) {
                return ($did, $description);
            }
        }
     }
     $c->finish;
    
     return undef;
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
        
        unless ($is_official && !$is_virtual)
        {
            my ($current_official) = $dbh->selectrow_array(qq~
                SELECT title FROM contests
                  WHERE CATS_SYSDATE() BETWEEN start_date AND finish_date AND is_official = 1~);
            !$current_official
                or return msg(123, $current_official);
        }
    }
    
    my $src = '';

    my ($br, $buffer);
    while ($br = read($file, $buffer, 1024))
    {
        length $src < 32767
            or return msg(10);
        $src .= $buffer;
    }
    
    $src ne '' or return msg(11);

    my $did;

    if ( param('de_id') eq 'by_extension' )
    {
        ($did, my $de_name) = get_source_de($file);
        
        defined $did or return msg(13);
        
        $t->param( de_name => $de_name );
    }
    else
    {
        $did = param('de_id');
    }

    my $rid = new_id;
    
    my $submit_uid = $uid;
    if (!defined $submit_uid && $is_practice)
    {
        $submit_uid = $dbh->selectrow_array(qq~
            SELECT id FROM accounts WHERE login=?~, {}, $cats::anonymous_login);
    }

    $dbh->do(qq~
        INSERT INTO reqs(
          id, account_id, problem_id, contest_id, 
          submit_time, test_time, result_time, state, received
        ) VALUES(
          ?,?,?,?,CATS_SYSDATE(),CATS_SYSDATE(),CATS_SYSDATE(),?,?)~,
        {}, $rid, $submit_uid, $pid, $cid, $cats::st_not_processed, 0);
    
    my $s = $dbh->prepare(qq~INSERT INTO sources(req_id, de_id, src, fname) VALUES (?,?,?,?)~ );
    $s->bind_param(1, $rid);
    $s->bind_param(2, $did);
    $s->bind_param(3, $src, { ora_type => 113 } ); # blob
    $s->bind_param(4, "$file");
    $s->execute;

    $dbh->commit;
    $t->param(solution_submitted => 1, href_console => url_f('console'));
    msg(15);
}



sub problems_submit_std_solution
{
    my $pid = param('problem_id');

    unless (defined $pid)
    {
        msg(12);
        return;
    }

    my $ok = 0;
    
    my $c = $dbh->prepare(qq~SELECT src, de_id, fname 
                            FROM problem_sources 
                            WHERE problem_id=? AND (stype=? OR stype=?)~);
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


sub problems_frame 
{
    my $show_packages = 1;
    unless ($is_jury)
    {
        (my $start_diff_time, $show_packages) = $dbh->selectrow_array(qq~
            SELECT CATS_SYSDATE() - start_date, show_packages FROM contests WHERE id=?~,
            {}, $cid);
        if ($start_diff_time < 0) 
        {
            init_template( 'main_problems_inaccessible.htm' );      
            $t->param(problems_inaccessible => 1);
            return;
        }
    }

    if (defined url_param('new') && $is_jury)
    {
        problems_new_frame;
        return;
    }

    if (defined url_param('link') && $is_jury)
    {
        problems_link_frame;
        return;
    }

    if (defined url_param('delete') && $is_jury)
    {
        my $cpid = url_param('delete');
        my $pid = $dbh->selectrow_array(qq~SELECT problem_id FROM contest_problems WHERE id=?~, {}, $cpid);

        $dbh->do(qq~DELETE FROM contest_problems WHERE id=?~, {}, $cpid);
        $dbh->commit;       

        unless ($dbh->selectrow_array(qq~SELECT COUNT(*) FROM contest_problems WHERE problem_id=?~, {}, $pid))
        {
            $dbh->do(qq~DELETE FROM problems WHERE id=?~, {}, $pid);
            $dbh->commit;       
        }
    }

    if (defined param('download') && $show_packages)
    {
        download_problem;
        return;
    }

    init_listview_template( "problems$cid" . ($uid || ''), 'problems', 'main_problems.htm' );      

    if (defined param('link_save') && $is_jury)
    {
        problems_link_save;
    }

    if (defined param('new_save') && $is_jury)
    {
        problems_new_save;
    }

    if (defined param('change_status') && $is_jury)
    {
        problems_change_status;
    }

    if (defined param('replace_direct') && $is_jury)
    {
        problems_replace_direct;
    }

    if (defined param('submit'))
    {
        problems_submit;
    }

    if (defined param('std_solution') && $is_jury)
    {
        problems_submit_std_solution;
    }

    if (defined param('mass_retest') && $is_jury)
    {
        problems_mass_retest;
    }

    my @cols = (
        { caption => res_str(602), order_by => '3', width => '30%' },
        ($is_jury ?
        (
            { caption => res_str(632), order_by => '9, 8', width => '5%' },
            { caption => res_str(635), order_by => '11', width => '10%' },
            { caption => res_str(634), order_by => '10', width => '10%' },
        )
        : ()
        ),
        ($is_practice ?
        { caption => res_str(603), order_by => '4', width => '30%' } : ()
        ),
        { caption => res_str(604), order_by => '5', width => '5%' },
        { caption => res_str(605), order_by => '6', width => '5%' },
        { caption => res_str(606), order_by => '7', width => '5%' }
    );
    define_columns(url_f('problems'), 0, 0, [ @cols ]);

    my $reqs_count_sql = 'SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state =';
    my $account_condition = $is_practice ? '' : ' AND D.account_id = ?';
    my $select_code = $is_practice ? '' : q~CP.code || ' - ' || ~;
    my $hidden_problems = $is_jury ? '' : " AND (CP.status IS NULL OR CP.status < $cats::problem_st_hidden)";
    my $sth = $dbh->prepare(qq~
        SELECT
          CP.id AS cpid, P.id AS pid,
          ${select_code}P.title AS problem_name, OC.title AS contest_name,
          ($reqs_count_sql $cats::st_accepted$account_condition) AS accepted_count,
          ($reqs_count_sql $cats::st_wrong_answer$account_condition) AS wrong_answer_count,
          ($reqs_count_sql $cats::st_time_limit_exceeded$account_condition) AS time_limit_count,
          P.contest_id - CP.contest_id AS is_linked, CP.status,
          OC.id AS original_contest_id, CP.status,
          CATS_DATE(P.upload_date) AS upload_date,
          (SELECT A.login FROM accounts A WHERE A.id = P.last_modified_by) AS last_modified_by
        FROM problems P, contest_problems CP, contests OC
        WHERE CP.problem_id = P.id AND OC.id = P.contest_id AND CP.contest_id = ?$hidden_problems
        ~ . order_by
    );
    if ($is_practice)
    {
        $sth->execute($cid);
    }
    else
    {
        my $aid = $uid || 0; # на случай анонимного пользователя
        # опять баг с порядком параметров
        $sth->execute($cid, $aid, $aid, $aid);
    }

    my $fetch_record = sub($)
    {            
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
        return (
            href_delete   => url_f('problems', delete => $c->{cpid}),
            href_replace  => url_f('problems', replace => $c->{cpid}),
            href_download => url_f('problems', download => $c->{pid}),
            show_packages => $show_packages,
            is_practice => $is_practice,
            editable => $is_jury,
            status => problem_status_names()->{$c->{status}},
            disabled => !$is_jury && $c->{status} == $cats::problem_st_disabled,
            is_team => $is_team || $is_practice,
            href_view_problem => url_f('problem_text', cpid => $c->{cpid}),
            
            problem_id => $c->{pid},
            problem_name => $c->{problem_name},
            is_linked => $c->{is_linked},
            contest_name => $c->{contest_name},
            accept_count => $c->{accepted_count},
            wa_count => $c->{wrong_answer_count},
            tle_count => $c->{time_limit_count},
            upload_date => $c->{upload_date},
            last_modified_by => $c->{last_modified_by}
        );
    };
            
    attach_listview(url_f('problems'), $fetch_record, $sth);

    $sth->finish;

    $sth = $dbh->prepare(qq~SELECT id, description FROM default_de WHERE in_contests=1 ORDER BY code~);
    $sth->execute;

    my @de = ({ de_id => "by_extension", de_name => res_str(536) });

    while (my ($de_id, $de_name) = $sth->fetchrow_array)
    {
        push @de, { de_id => $de_id, de_name => $de_name };
    }

    $sth->finish;
    
    my @submenu = ( { href_item => url_f('problem_text'), item_name => res_str(538), item_target=>'_blank' } );

    if ($is_jury)
    {
        my $n = problem_status_names();
        my $status_list = [];
        for (sort keys %$n)
        {
            push @$status_list, { id => $_, name => $n->{$_} }; 
        }
        $t->param(
            status_list => $status_list,
            editable => 1
        );

        push @submenu, (
            { href_item => url_f('problems', new => 1), item_name => res_str(539) },
            { href_item => url_f('problems', link => 1), item_name => res_str(540) } );
    }

    $t->param(submenu => [ @submenu ]);
    $t->param(is_team => ($is_team || $is_practice), is_practice => $is_practice, de_list => [ @de ]);
}



sub users_new_frame 
{
    init_template('main_users_new.htm');
    $t->param(login => generate_login);
    $t->param(countries => [ @cats::countries ], href_action => url_f('users'));    
}


sub user_param_names ()
{
    qw(login team_name captain_name email country motto home_page icq_number)
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
        length $up->{password1} <= 100
            or return msg(102);

        $up->{password1} eq $up->{password2}
            or return msg(33);
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
            id, srole, passwd,
            login, team_name, capitan_name, country, motto, email, home_page, icq_number
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

    my $countries = [ @cats::countries ];

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
    my $set_password = param('set_password') eq 'on';
    my $id = param('id');

    user_validate_params(\%up, validate_password => $set_password) or return;

    $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM accounts WHERE id <> ? AND login = ?~, {}, $id, $up{login}
    ) and return msg(103);
 
    $dbh->do(qq~
        UPDATE accounts
            SET login = ?, team_name = ?, capitan_name = ?, country = ?,
                motto = ?, email = ?, home_page = ?, icq_number = ?
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
        next if param("msg$_") ne 'on';
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

            unless ($dbh->selectrow_array(qq~SELECT COUNT(*) FROM contest_accounts WHERE account_id=?~, {}, $aid))
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
        foreach (split(':', param('user_set')))
        {
            my $jury = param( "jury$_" ) eq 'on';
            my $ooc = param( "ooc$_" ) eq 'on';
            my $remote = param( "remote$_" ) eq 'on';
            my $hidden = param( "hidden$_" ) eq 'on';

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
        if (param('send_message_all') eq 'on')
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

    my $c;
    if ($is_jury)
    {
        $c = $dbh->prepare(qq~
            SELECT A.id, CA.id, A.country, A.login, A.team_name, 
               CA.is_jury, CA.is_ooc, CA.is_remote, CA.is_hidden, CA.is_virtual, A.motto,
               (SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
                WHERE R.state = $cats::st_accepted AND R.account_id=A.id AND R.contest_id=C.id)
            FROM accounts A, contest_accounts CA, contests C
            WHERE CA.account_id=A.id AND CA.contest_id=C.id AND C.id=?
            ~.order_by);

        $c->execute($cid);
    }
    elsif ($is_team)
    {
        $c = $dbh->prepare(qq~
            SELECT A.id, CA.id, A.country, A.login, A.team_name, 
                CA.is_jury, CA.is_ooc, CA.is_remote, CA.is_hidden, CA.is_virtual, A.motto,
                (SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
                    WHERE R.state = $cats::st_accepted AND R.account_id=A.id 
                    AND R.contest_id=C.id AND (R.submit_time < C.freeze_date OR C.defreeze_date < CATS_SYSDATE())
                )
            FROM accounts A, contest_accounts CA, contests C
            WHERE CA.account_id=A.id AND CA.contest_id=C.id AND C.id=? AND CA.is_hidden=0 
            ~.order_by);
                   
        $c->execute($cid);
    }
    else
    {
        $c = $dbh->prepare(qq~
            SELECT A.id, CA.id, A.country, A.login, A.team_name, 
                CA.is_jury, CA.is_ooc, CA.is_remote, CA.is_hidden, CA.is_virtual, A.motto, 
                (SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
                    WHERE R.state = $cats::st_accepted AND R.account_id=A.id 
                    AND R.contest_id=C.id AND (R.submit_time < C.freeze_date OR C.defreeze_date < CATS_SYSDATE())
                ) 
            FROM accounts A, contest_accounts CA, contests C
            WHERE C.id=? AND CA.account_id=A.id AND CA.contest_id=C.id AND CA.is_hidden=0
            ~.order_by);

        $c->execute($cid);
    }

    my $fetch_record = sub($)
    {            
        my (
            $aid, $caid, $country_abb, $login, $team_name, $jury, $ooc, $remote, $hidden, $virtual, $motto, $accepted
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
    };

    $c->finish;
}


sub registration_frame {

    init_template('main_registration.htm');

    $t->param(countries => [ @cats::countries ], href_login => url_f('login'));

    if (defined param('register'))
    {
        my $login = param('login');
        my $team_name = param('team_name');
        my $capitan_name = param('capitan_name');       
        my $email = param('email');     
        my $country = param('country'); 
        my $motto = param('motto');
        my $home_page = param('home_page');     
        my $icq_number = param('icq_number');
        my $password1 = param('password1');
        my $password2 = param('password2');

        unless ($login && length $login <= 100)
        {
            msg(101);
            return;
        }

        unless ($team_name && length $team_name <= 100)
        {
            msg(43);
            return;
        }

        if (length $capitan_name > 100)
        {
            msg(45);
            return;
        }

        if (length $motto > 200)
        {
            msg(44);
            return;
        }

        if (length $home_page > 100)
        {
            msg(48);
            return;
        }

        if (length $icq_number > 100)
        {
            msg(47);
            return;
        }

        if (length $password1 > 100)
        {
            msg(102);
            return;
        }          

        unless ($password1 eq $password2)
        {
            msg(33);
            return;
        }

        if ($dbh->selectrow_array(qq~SELECT COUNT(*) FROM accounts WHERE login=?~, {}, $login))
        {
            msg(103);
            return;       
        }

        my $aid = new_id;
            
        $dbh->do(qq~INSERT INTO accounts (
            id, login, passwd, srole, team_name, capitan_name, country, motto, email, home_page, icq_number) 
            VALUES(?,?,?,?,?,?,?,?,?,?,?)~, {},
            $aid, $login, $password1, $cats::srole_user, $team_name, $capitan_name, $country, $motto, $email, $home_page, $icq_number);

        my $c = $dbh->prepare(qq~SELECT id, closed FROM contests WHERE ctype=1~);
        $c->execute;
        while (my ($cid, $closed) = $c->fetchrow_array)
        {
            if ($closed)
            {
                msg(105);
                $dbh->rollback;
                return;
            }
            $dbh->do(qq~
                INSERT INTO contest_accounts (
                    id, contest_id, account_id, is_jury, is_pop, is_hidden, is_ooc, is_remote
                ) VALUES(?,?,?,?,?,?,?,?)~, {},
                new_id, $cid, $aid, 0, 0, 0, 1, 0);
        }
           
        $dbh->commit;
        $t->param(successfully_registred => 1);
    }
}


sub settings_save
{
    my $login = param('login');
    my $team_name = param('team_name');
    my $capitan_name = param('capitan_name');       
    my $email = param('email');     
    my $country = param('country'); 
    my $motto = param('motto');
    my $home_page = param('home_page');     
    my $icq_number = param('icq_number');
    my $set_password = (param('set_password') || '') eq 'on';
    my $password1 = param('password1');
    my $password2 = param('password2');

    unless ($login && length $login <= 100)
    {
        msg(101);
        return;
    }

    unless ($team_name && length $team_name <= 100)
    {
        msg(43);
        return;
    }

    if (length $capitan_name > 100)
    {
        msg(45);
        return;
    }

    if (length $motto > 500)
    {
        msg(44);
        return;
    }

    if (length $home_page > 100)
    {
        msg(48);
        return;
    }

    if (length $icq_number > 100)
    {
        msg(47);
        return;
    }

    if ($dbh->selectrow_array(qq~SELECT COUNT(*) FROM accounts WHERE id<>? AND login=?~, {}, $uid, $login))
    {
        msg(103);
        return;       
    }
 
    $dbh->do(qq~UPDATE accounts SET login=?, team_name=?, capitan_name=?, country=?, motto=?, email=?, home_page=?, icq_number=?
         WHERE id=?~, {}, $login, $team_name, $capitan_name, $country, $motto, $email, $home_page, $icq_number, $uid);

    $dbh->commit;       


    if ($set_password)
    {        
        if (length $password1 > 50)
        {
            msg(102);
            return;
        }

        unless ($password1 eq $password2)
        {
            msg(33);
            return;
        }
        
        $dbh->do(qq~UPDATE accounts SET passwd=? WHERE id=?~, {}, $password1, $uid);
        $dbh->commit; 
    }
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
        { name => 'keywords', new => 549, item => 549 },
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
    my $locked = param('locked') eq 'on';
            
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
    my $locked = param('locked') eq 'on';
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
    my $locked = param('locked') eq 'on';
    
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
    my ($judge_name, $lock_counter) = $dbh->selectrow_array(qq~SELECT nick, lock_counter FROM judges WHERE id=?~, {}, $jid);
    $t->param(id => $jid, judge_name => $judge_name, locked => $lock_counter, href_action => url_f('judges'));
}


sub judges_edit_save
{
    my $jid = param('id');
    my $judge_name = param('judge_name');
    my $locked = param('locked') eq 'on';
    
    if ($judge_name eq '' || length $judge_name > 20)
    {
        msg 5;
        return;
    }
  
    $dbh->do(qq~UPDATE judges SET nick=?, lock_counter=? WHERE id=?~, {}, 
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


sub keywords_frame
{
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
                VALUES (?,CATS_SYSDATE(),?,?,0)~);
        $s->bind_param(1, new_id );
        $s->bind_param(2, $message_text, { ora_type => 113 } );
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

    my $caid = $dbh->selectrow_array(qq~SELECT account_id FROM questions WHERE id=?~, {}, $qid);
    my $aid = $dbh->selectrow_array(qq~SELECT account_id FROM contest_accounts WHERE id=?~, {}, $caid);
    my $team_name = $dbh->selectrow_array(qq~SELECT login FROM accounts WHERE id=?~, {}, $aid);

    $t->param(team_name => $team_name);

    if (defined param('clarify'))
    {
        my $answer_text = param('answer_text');

        my $s = $dbh->prepare(qq~
            UPDATE questions
                SET clarification_time=CATS_SYSDATE(), answer=?, received=0, clarified=1
                WHERE id = ?~);
        $s->bind_param(1, $answer_text, { ora_type => 113 } );
        $s->bind_param(2, $qid);
        $s->execute;
        $dbh->commit;
        $t->param(clarified => 1);
    }
    else
    {
        my ($submit_time, $question_text) = 
            $dbh->selectrow_array(qq~
                SELECT CATS_DATE(submit_time), question FROM questions WHERE id=?~, {}, $qid);
    
        $t->param(submit_time => $submit_time, question_text => $question_text);
    }
}


sub source_links
{
    my ($si, $is_jury) = @_;
    my ($current_link) = param('f') || '';
    
    $si->{href_contest_problems} =
        url_function('problems', cid => $si->{contest_id}, sid => $sid);
    for (qw/run_details view_source run_log/)
    {
        next if $_ eq $current_link;
        $si->{"href_$_"} = url_f($_, rid => $si->{req_id});
        $si->{is_jury} = $is_jury;
    }
    $t->param(is_jury => $is_jury);
    if ($is_jury && $si->{judge_id})
    {
        $si->{judge_name} = get_judge_name($si->{judge_id});
    }
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
            $row->{checker_comment} = Encode::decode('utf8', $d, Encode::FB_QUIET);
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
    $t->param(run_details => [
        map {
            exists $run_details{$_} ? $run_details{$_} :
            $contest->{show_all_tests} ? { test_rank => $_, not_processed => 1 } :
            () 
        } (1..$last_test)
    ]);
}


sub view_source_frame
{
    init_template('main_view_source.htm');
    my $rid = url_param('rid') or return;

    my $sources_info = get_sources_info(request_id => $rid, get_source => 1)
        or return;

    my $is_jury = is_jury_in_contest(contest_id => $sources_info->{contest_id});
    $is_jury || $sources_info->{account_id} == $uid
        or return msg(126);

    source_links($sources_info, $is_jury);
    $t->param(sources_info => [$sources_info]);
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
        } -> {param 'state'};

        my $failed_test = sprintf '%d', param('failed_test');
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

    my $previous_attempt = $dbh->selectrow_hashref(qq~
        SELECT id, CATS_DATE(submit_time) AS submit_time FROM reqs
          WHERE account_id = ? AND problem_id = ? AND id < ?
          ORDER BY id DESC~, { Slice => {} },
        $si->{account_id}, $si->{problem_id}, $rid
    );
    for ($previous_attempt)
    {
        last unless defined $_;
        $_->{submit_time} =~ s/\s*$//;
        $t->param(
            href_previous_attempt => url_f('run_log', rid => $_->{id}),
            previous_attempt_time => $_->{submit_time},
            href_diff_runs => url_f('diff_runs', r1 => $_->{id}, r2 => $rid),
        );
    }

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
    
    my $SL = sub { $si->[$_[0]]->{lines}->[$_[1]] }; 
    
    my $match = sub { push @diff, $SL->(0, $_[0]) . "\n"; };
    my $only_a = sub { push @diff, span({class=>'diff_only_a'}, $SL->(0, $_[0]) . "\n"); };
    my $only_b = sub { push @diff, span({class=>'diff_only_b'}, $SL->(1, $_[1]) . "\n"); };

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
        FROM
            reqs R INNER JOIN req_details RD ON RD.req_id = R.id
            INNER JOIN tests T ON RD.test_rank = T.rank AND T.problem_id = R.problem_id
        WHERE R.id = ?~, { Slice => {} },
        $req_id
    );
    
    my $total = 0;
    for (@$points)
    {
        $total += $_->{result} == $cats::st_accepted ? ($_->{points} || 1) : 0;
    }
    
    $dbh->do(q~UPDATE reqs SET points = ? WHERE id = ?~, undef, $total, $req_id);
    $total;
}


sub cache_max_points
{
    my ($pid) = @_;
    my ($max_points) = $dbh->selectrow_array(q~
        SELECT SUM(points) FROM tests WHERE problem_id = ?~, undef, $pid);
    $dbh->do(q~UPDATE problems SET max_points = ? WHERE id = ?~, undef, $max_points, $pid);
    $max_points;
}


sub rank_get_problem_ids
{
    my ($contest_list, $show_points) = @_;
    # соответствующее требование: в одном чемпионате задача не должна дублироваться обеспечивается
    # при помощи UNIQUE(c,p)
    my $hidden_problems = $is_jury ? '' : ' AND CP.status < ?';
    my $problems = $dbh->selectall_arrayref(qq~
        SELECT
            CP.id, CP.problem_id, CP.code, CP.contest_id, CATS_DATE(C.start_date) AS start_date,
            C.start_date - CATS_SYSDATE() AS since_start, P.max_points, P.title
        FROM
            contest_problems CP INNER JOIN contests C ON C.id = CP.contest_id
            INNER JOIN problems P ON P.id = CP.problem_id
        WHERE CP.contest_id IN ($contest_list)$hidden_problems
        ORDER BY C.start_date, CP.code~, { Slice => {} },
        ($is_jury ? () : $cats::problem_st_hidden)
    );

    my $w = int(50 / (@$problems + 1));
    $w = $w < 3 ? 3 : $w > 10 ? 10 : $w;

    $_->{column_width} = $w for @$problems;

    my @contests = ();
    my $prev_cid = -1;
    my $need_commit = 0;
    for (@$problems)
    {
        if ($_->{contest_id} != $prev_cid)
        {
            $_->{start_date} =~ /^\s*(\S+)/;
            push @contests, { start_date => $1, count => 1 };
            $prev_cid = $_->{contest_id};
        }
        else
        {
            $contests[$#contests]->{count}++;
        }
        $_->{title} = '' if $_->{since_start} < 0 && !$is_jury;
        $_->{problem_text} = url_f('problem_text', cpid => $_->{id});
        if ($show_points && !$_->{max_points})
        {
            $_->{max_points} = cache_max_points($_->{problem_id});
            $need_commit = 1;
        }
    }
    $dbh->commit if $need_commit;

    $t->param(
        problems => $problems,
        problem_column_width => $w,
        contests => [ @contests ],
        many_contests => @contests > 1
    );
    
    map { $_->{problem_id} } @$problems;
}


sub rank_get_results
{
    my ($frozen, $contest_list, $cond_str) = @_;
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
    if (!$is_jury)
    {
        push @conditions, 'CP.status < ?';
        push @params, $cats::problem_st_hidden;
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
            CA.is_hidden = 0 AND R.state >= ? AND C.id IN ($contest_list)$cond_str
        ORDER BY R.id~, { Slice => {} },
        $cats::request_processed, @params
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
    
    my @p = ('rank_table', clist => $contest_list);
    $t->param(
        not_started => $not_started && !$is_jury,
        frozen => $frozen,
        hide_ooc => !$hide_ooc,
        hide_virtual => !$hide_virtual,
        href_hide_ooc => url_f(@p, hide_ooc => 1, hide_virtual => $hide_virtual),
        href_show_ooc => url_f(@p, hide_ooc => 0, hide_virtual => $hide_virtual),
        href_hide_virtual => url_f(@p, hide_virtual => 1, hide_ooc => $hide_ooc),
        href_show_virtual => url_f(@p, hide_virtual => 0, hide_ooc => $hide_ooc),
        show_points => $show_points
    );
    #return if $not_started;

    my $virtual_cond = $hide_virtual ? ' AND CA.is_virtual = 0' : '';
    my $ooc_cond = $hide_ooc ? ' AND CA.is_ooc = 0' : '';
    my $teams = $dbh->selectall_hashref(qq~
        SELECT
            A.team_name, A.motto, A.country,
            MAX(CA.is_virtual) AS is_virtual, MAX(CA.is_ooc) AS is_ooc, MAX(CA.is_remote) AS is_remote,
            CA.account_id
        FROM accounts A, contest_accounts CA
        WHERE CA.contest_id IN ($contest_list) AND A.id = CA.account_id AND CA.is_hidden = 0
            $virtual_cond $ooc_cond
        GROUP BY CA.account_id, A.team_name, A.motto, A.country~, 'account_id', { Slice => {} }
    );

    my @p_id = rank_get_problem_ids($contest_list, $show_points);
    $t->param(
        problem_colunm_width =>
            @p_id <= 6 ? 6 :
            @p_id <= 8 ? 5 :
            @p_id <= 10 ? 4 :
            @p_id <= 20 ? 3 : 2
    );
    my $problems =
        { map { $_ => {total_runs => 0, total_accepted => 0, total_points => 0} } @p_id };

    for my $team (values %$teams)
    {
        # поскольку виртуальный участник всегда ooc, не выводим лишнюю строчку
        $team->{is_ooc} = 0 if $team->{is_virtual};
        $team->{$_} = 0 for qw(total_solved total_runs total_time total_points);
        ($team->{country}, $team->{flag}) = get_flag($_->{country});
        my %init_problem = (runs => 0, time_consumed => 0, solved => 0, points => undef);
        $team->{problems} = { map { $_ => { %init_problem } } @p_id };
    }

    my $results = rank_get_results($frozen, $contest_list, $virtual_cond . $ooc_cond);
    my $need_commit = 0;
    for (@$results)
    {
        my $t = $teams->{$_->{account_id}};
        my $p = $t->{problems}->{$_->{problem_id}};
        if ($show_points && !defined $_->{points})
        {
            $_->{points} = cache_req_points($_->{id});
            $need_commit = 1;
        }
        next if $p->{solved} && !$show_points;

        if ($_->{state} == $cats::st_accepted)
        {
            $p->{time_consumed} = int($_->{time_elapsed} + 0.5) + $p->{runs} * $cats::penalty;
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
            $t->{total_points} += $_->{points} - $p->{points};
            $problems->{$_->{problem_id}}->{total_points} += $_->{points} - $p->{points};
            $p->{points} = $_->{points};
        }
    }

    $dbh->commit if $need_commit;

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
                td => $c, 'time' => ($p->{time_consumed} || ''),
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
    }

    $t->param(
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
    $t->param(rank_table_content => $s);
}


sub rank_table_frame
{
    my $hide_ooc = url_param('hide_ooc') || 0;
    my $hide_virtual = url_param('hide_virtual') || 0;
    my $show_points = url_param('points');
    
    #rank_table('main_rank_table.htm');  
    my $print = url_param('print') ? '_print' : '';
    #init_template("main_rank_table_content$t.htm");
    init_template("main_rank_table$print.htm");  
        
    my $contest_list = get_contest_list_param;
    ($contest_title) = get_contests_info($contest_list, $uid);

    $t->param(href_rank_table_content => url_f(
        'rank_table_content',
        hide_ooc => $hide_ooc, hide_virtual => $hide_virtual, clist => $contest_list,
        points => $show_points
    ));
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


# генерация страницы с текстом задач
sub start_element 
{
    my ($el, %atts) = @_;

    $html_code .= "<$el";
    foreach my $name (keys %atts)
    {
        $name = $name;
        my $attrib = $atts{$name};

        $html_code .= " $name=\"$attrib\"";
    }
    $html_code .= ">";
}


sub end_element 
{
    my ( $el ) = @_;    

    $html_code .= "</$el>";
}


sub text
{
    my ( $text ) = shift;
    
    $html_code .= $text;
}


sub ch_1
{
    my ( $p, $text ) = @_;
        
    text( $text );
}


sub download_image
{
    my $id = shift;

    my $download_dir = './download';

    my ($pic, $ext) = $dbh->selectrow_array(qq~SELECT pic, extension FROM pictures WHERE id=?~, {}, $id);

    my ($fh, $fname) = tempfile(
        "img_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX", 
        DIR => $download_dir, SUFFIX => ".$ext");

    binmode(STDOUT, ':raw');

    syswrite($fh, $pic, length($pic));    

    close $fh;
    
    return $fname;
}

sub sh_1
{
    my ($p, $el, %atts) = @_;
    
    if ($el eq 'img' && $atts{'picture'})
    {
        my ($id) = $dbh->selectrow_array(qq~
            SELECT id FROM pictures WHERE problem_id=? AND name=?~, {},
            $current_pid, $atts{'picture'});

        $atts{src} = download_image($id);
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

    $html_code = "";

    $parser->setHandlers(
        'Start' => \&sh_1,
        'End'   => \&eh_1,
        'Char'  => \&ch_1);
                
    $parser->parse( "<p>$xml_patch</p>" );
    return $html_code;    
}


sub contest_visible 
{  
    return 1 if $is_jury;
    my $contest_visible = 0;

    my $pid = url_param('pid');
    my $cpid = url_param('cpid');

    if (defined $pid)
    {
        $contest_visible = $dbh->selectrow_array(qq~
            SELECT CATS_SYSDATE() - B.start_date
                FROM problems A, contests B 
                WHERE A.id=? AND B.id = A.contest_id~, {}, $pid) > 0;
    }
    elsif (defined $cpid)
    {
        $contest_visible = $dbh->selectrow_array(qq~
            SELECT CATS_SYSDATE() - B.start_date
                FROM contest_problems A, contests B 
                WHERE A.id=? AND B.id = A.contest_id~, {}, $cpid) > 0;
    
    }
    elsif (defined $cid)
    {
        $contest_visible = $dbh->selectrow_array(qq~
            SELECT CATS_SYSDATE() - A.start_date
                FROM contests A
                WHERE A.id=?~, {}, $cid) > 0;
    }

    init_template('main_access_denied.htm') if !$contest_visible;
    return $contest_visible;
}    


sub problem_text_frame
{
    contest_visible() or return;

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
            $cpid);    
        push @id_problems, $problem_id;
        $pcodes{$problem_id} = $code;
    }
    else
    {    
        ($show_points) = $dbh->selectrow_array(q~
            SELECT rules FROM contests WHERE id = ?~, undef, $cid);

        my $c = $dbh->prepare(qq~
            SELECT problem_id, code FROM contest_problems
            WHERE contest_id=? ORDER BY code~);
        $c->execute($cid);
        while (my ($problem_id, $code) = $c->fetchrow_array)
        {
            push @id_problems, $problem_id;
            $pcodes{$problem_id} = $code;
        }
    }


    my $need_commit = 0;
    for my $problem_id (@id_problems)
    {
        $current_pid = $problem_id;
        
        my $problem_data = $dbh->selectrow_hashref(qq~
            SELECT
                id, contest_id, title, lang, time_limit, memory_limit,
                difficulty, author, input_file, output_file,
                statement, pconstraints, input_format,
                output_format, max_points
            FROM problems WHERE id = ?~, { Slice => {} },
            $problem_id);
        if ($show_points && !$problem_data->{max_points})
        {
            $problem_data->{max_points} = cache_max_points($problem_data->{id});
            $need_commit = 1;
        }

        $problem_data->{samples} = $dbh->selectall_arrayref(qq~
            SELECT rank, in_file, out_file
            FROM samples WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
            $problem_id);

        for my $field_name qw(statement pconstraints input_format output_format)
        {
            for ($problem_data->{$field_name})
            {
                $_ = $_ eq '' ? undef : Encode::encode_utf8(parse($_));
                CATS::TeX::Lite::convert_all($_);
                s/-{2,3}/&#151;/g; # тире
            }
        }
        my $lang = $problem_data->{lang};
        push @problems,  {
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
    
    my $rid = url_param('rid');

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
    my $problem_count = $dbh->selectrow_array(qq~SELECT COUNT(*) FROM problems~);
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
                is_practice => $is_practice,
                editable => $is_jury,
                is_team => $is_team || $is_practice,
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
        { item => res_str(510), href => url_f('console') },
    );   

    if ($is_jury)
    {
        push @left_menu, (
            { item => res_str(548), href => url_f('compilers') },
            { item => res_str(545), href => url_f('cmp') } );
    }
    else
    {
        push @left_menu, { item => res_str(517), href => url_f('compilers') };
    }

    if (!$is_practice)
    {
        push @left_menu, ( { item => res_str(529), href => url_f('rank_table') } );

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
        users => \&users_frame,
        compilers => \&compilers_frame,
        judges => \&judges_frame,
        keywords => \&keywords_frame,
        answer_box => \&answer_box_frame,
        send_message_box => \&send_message_box_frame,
        
        run_log => \&run_log_frame,
        view_source => \&view_source_frame,
        run_details => \&run_details_frame,
        diff_runs => \&diff_runs_frame,
        
        rank_table_content => \&rank_table_content_frame,
        rank_table => \&rank_table_frame,
        rank_problem_details => \&rank_problem_details,
        problem_text => \&problem_text_frame,
        envelope => \&envelope_frame,
        about => \&about_frame,
        authors => \&authors_frame,
        
        'cmp' => \&cmp_frame,
    }
}


sub accept_request                                               
{     
    initialize;

    my $function_name = url_param('f') || '';
    my $fn = interface_functions()->{$function_name} || \&about_frame;
    $fn->();

    generate_menu if (defined $t);
    generate_output;

}
         
sql_connect;

#while(CGI::Fast->new)
#{  
#    accept_request;    
#    exit if (-M $ENV{ SCRIPT_FILENAME } < 0); 
#}
#eval
    { accept_request; };

$dbh->rollback;
sql_disconnect;

1;
