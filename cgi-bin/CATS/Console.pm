package CATS::Console;

use strict;
use warnings;

use CGI qw(:standard);;
use List::Util;

use CATS::DB;
use CATS::Misc qw(:all);
use CATS::Data qw(:all);

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


sub get_time_interval
{
    my $s = $settings->{$listview_name};
    $s->{i_value} = coalesce(param('i_value'), $s->{i_value}, 1);
    $s->{i_unit} = param('i_unit') || $s->{i_unit} || 'hours';
}


sub time_interval_days
{
    get_time_interval;
    my ($v, $u) = @{$settings->{$listview_name}}{qw(i_value i_unit)};
    my @text = split /\|/, res_str(121);
    my $units = [
        { value => 'hours', k => 1 / 24 },
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
        'i_values' => [
            map { {value => $_, text => $_ || 'all', selected => $v eq $_} } (1..5, 10, 0)
        ],
        'i_units' => $units
    );

    return $v > 0 ? $v * $selected_unit->{k} : 100000;
}


sub console
{
    my $template_name = shift;
    init_listview_template('console', 'console', 'main_console_content.htm');

    my $day_count = time_interval_days;
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
            state_to_display($request_state,
                # security: во время соревноваиня не показываем участникам
                # конкретные результаты других команд, а только accepted/rejected
                $contest->{time_since_defreeze} <= 0 && !$is_jury &&
                (!$is_team || !$team_id || $team_id != $uid)),
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
        url_f('console'), $fetch_console_record, $c, { page_params => { uf => $user_filter } });

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
        $dbh->commit; # Минимизируем шанс deadlock'а
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


sub select_all_reqs
{
    my ($extra_cond) = @_;
    $dbh->selectall_arrayref(qq~
        SELECT
            R.id AS id, CATS_DATE(R.submit_time) AS submit_time, R.state, R.failed_test,
            R.submit_time - C.start_date AS time_since_start,
            CP.code, P.title AS problem_title,
            A.id AS team_id, A.team_name, A.last_ip,
            CA.is_remote, CA.is_ooc
        FROM
            reqs R INNER JOIN
            problems P ON R.problem_id = P.id INNER JOIN
            contest_accounts CA ON CA.contest_id = R.contest_id AND CA.account_id = R.account_id INNER JOIN
            contests C ON R.contest_id = C.id INNER JOIN
            contest_problems CP ON R.contest_id = CP.contest_id AND CP.problem_id = R.problem_id INNER JOIN
            accounts A ON CA.account_id = A.id
        WHERE
            R.contest_id = ? AND CA.is_hidden = 0 AND CA.diff_time = 0$extra_cond
        ORDER BY R.submit_time ASC~, { Slice => {} },
        $cid);
}


sub export
{
    $is_jury or return;
    init_template('main_console_export.xml');
    my $reqs = select_all_reqs;
    for my $req (@$reqs)
    {
        $req->{submit_time} =~ s/\s+$//;
        my %st = state_to_display($req->{state});
        for (keys %st)
        {
            $st{$_} or next;
            $req->{state} = $_;
            last;
        }
        $req->{s} = join '', map "<$_>$req->{$_}</$_>", grep defined $req->{$_}, keys %$req;
    }
    $t->param(reqs => $reqs);
}


sub graphs
{
    $is_jury or return;
    init_template('main_console_graphs.htm');
    my $codes = $dbh->selectcol_arrayref(q~
        SELECT CP.code FROM contest_problems CP WHERE CP.contest_id = ? ORDER BY 1~, undef,
        $cid);
    #push @$codes, 'all';
    $_ = { code => $_, selected => 1 } for @$codes;
    my $steps_per_hour = (param('steps') || 1) + 0;
    my $accepted_only = param('accepted_only') || 0;
    $t->param(
        submenu => [ { href_item => url_f('console'), item_name => res_str(510) } ],
        codes => $codes,
        href_graphs => url_f('console_graphs'),
        steps => $steps_per_hour,
        accepted_only => $accepted_only);
    param('do_graph') or return;
    
    my %selected_codes = map { $_ => 1 } param('selected_codes');
    for my $c (@$codes)
    {
        $c->{selected} = $selected_codes{$c->{code}};
    }
 
    my $reqs = select_all_reqs($accepted_only ? " AND R.state = $cats::st_accepted" : '');
    @$reqs or return;
    my $init_graph = sub { (code => $_[0], by_time => []) };
    my $graphs = { all => { $init_graph->('all') } };
    for my $req (@$reqs)
    {
        $req->{time_since_start} >= 0 && $selected_codes{$req->{code}} or next;
        my $g = $graphs->{$req->{code}} ||= { $init_graph->($req->{code}) };
        my $step = int($req->{time_since_start} * 24 * $steps_per_hour);
        $g->{by_time}->[$step]++;
        $graphs->{all}->{by_time}->[$step]++;
    }
    my @colors = ('0000ff', '00ff00', 'ff0000', '000000', 'ff00ff', '00ffff', 'ffa040', 'a0ff40', '800000', 'a040ff');
    my $ga = [ map $graphs->{$_}, sort keys %$graphs ];
    my $bt = $graphs->{all}->{by_time};
    $_ ||= 0 for @$bt;
    my $m = List::Util::max(@$bt);
    my $data = sub { join ',' => -1, map { ($_ || 0) / $m * 100 } @{$_[0]} };
    my %gp = (
      chs => '500x400',
      chd => 't:' . join('|', map $data->($_->{by_time}), @$ga),
      cht => 'lc',
      chco => join(',', map $colors[$_ % @colors], 0..@$ga),
      chdl => join('|', map $_->{code}, @$ga),
      chxt => 'x,y',
      chxl => '0:|' . join('|', map sprintf('%.1f', $_ / $steps_per_hour), 0..@$bt),
      chxr => "1,0,$m",
    );
    $t->param(graph => join '&amp;', map "$_=$gp{$_}", keys %gp);
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
    init_listview_template('console', 'console', 'main_console.htm');  
    get_time_interval;

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

    $t->param(
        href_console_content => url_f('console_content', uf => url_param('uf') || ''),
        is_team => $is_team,
        is_jury => $is_jury,
        question_text => $question_text,
        selection => $selection,
        href_view_source => url_f('view_source'),
        href_run_details => url_f('run_details'),
        href_run_log => url_f('run_log'),
        href_diff => url_f('diff_runs'),
        title_suffix => res_str(510),
    );
    $t->param(submenu => [
        { href_item => url_f('console_export'), item_name => res_str(561) },
        { href_item => url_f('console_graphs'), item_name => res_str(563) },
    ]) if $is_jury;
}


sub content_frame
{
    console('main_console_iframe.htm');  
}


1;
