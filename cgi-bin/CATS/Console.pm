package CATS::Console;

use strict;
use warnings;

use Encode qw(decode_utf8);
use List::Util;

use CATS::Countries;
use CATS::Data qw(:all);
use CATS::DB;
use CATS::ListView qw(init_listview_template attach_listview);
use CATS::Misc qw(
    $t $cid $is_team $is_jury $is_root $privs $uid $settings $listview_name $contest $sid
    get_anonymous_uid init_template url_f auto_ext res_str msg
);
use CATS::Request;
use CATS::Utils qw(coalesce url_function state_to_display date_to_iso);
use CATS::Web qw(param url_param);

sub send_question_to_jury
{
    my ($question_text) = @_;

    $is_team && defined $question_text && $question_text ne ''
        or return;
    length($question_text) <= 1000 or return msg(1063);

    my $cuid = get_registered_contestant(fields => 'id', contest_id => $cid);

    my ($previous_question_text) = $dbh->selectrow_array(q~
        SELECT question FROM questions WHERE account_id = ? ORDER BY submit_time DESC~, {},
        $cuid
    );
    ($previous_question_text || '') ne $question_text or return msg(1061);

    my $s = $dbh->prepare(q~
        INSERT INTO questions(id, account_id, submit_time, question, received, clarified)
        VALUES (?, ?, CURRENT_TIMESTAMP, ?, 0, 0)~
    );
    $s->bind_param(1, new_id);
    $s->bind_param(2, $cuid);
    $s->bind_param(3, $question_text, { ora_type => 113 } );
    $s->execute;
    $s->finish;
    $dbh->commit;
    msg(1062);
    1;
}


sub get_settings
{
    my $s = $settings->{$listview_name};
    $s->{i_value} = coalesce(param('i_value'), $s->{i_value}, 1);
    $s->{i_unit} = param('i_unit') || $s->{i_unit} || 'hours';
    $s->{show_results} = param('show_results') // $s->{show_results} // 1;
    $s->{show_messages} = param('show_messages') // $s->{show_messages} // 0;
    $s->{show_contests} = param('show_contests') // $s->{show_contests} // 0;
    $s;
}


sub time_interval_days
{
    my ($s) = @_;
    my ($v, $u) = @$s{qw(i_value i_unit)};
    my @text = split /\|/, res_str(1121);
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
            map { { value => $_, text => ($_ > 0 ? $_ : 'all'), selected => $v eq $_ } }
                (1..5, 10, -1)
        ],
        'i_units' => $units
    );

    return $v > 0 ? $v * $selected_unit->{k} : 100000;
}

sub init_console_template
{
    my ($template_name) = @_;
    my $se = param('se') || '';
    $se = "_$se" if $se;
    init_listview_template("console$se", 'console', $template_name);
}


sub console_content
{
    init_console_template(auto_ext('console_content'));

    my $s = get_settings;
    $s->{show_results} = 1 unless defined $s->{show_results};
    $s->{show_messages} = 1 unless defined $s->{show_messages};
    $t->param($_ => $s->{$_}) for qw(show_contests show_messages show_results);

    my $day_count = time_interval_days($s);
    my $dummy_account_block = q~
        CAST(NULL AS INTEGER) AS team_id,
        CAST(NULL AS VARCHAR(200)) AS team_name,
        CAST(NULL AS VARCHAR(30)) AS country,
        CAST(NULL AS VARCHAR(100)) AS last_ip,
        CAST(NULL AS INTEGER) AS caid,
        CAST(NULL AS INTEGER) AS contest_id
    ~;
    my $no_de = 'CAST(NULL AS VARCHAR(200)) AS de';
    my $city_sql = $is_jury ?
        q~ || (CASE WHEN A.city IS NULL OR A.city = '' THEN '' ELSE ' (' || A.city || ')' END)~ : '';
    my @contest_date_types = qw(start freeze finish);
    my %console_select = (
        run => qq~
            1 AS rtype,
            R.submit_time AS rank,
            R.submit_time,
            R.id AS id,
            R.state AS request_state,
            R.failed_test AS failed_test,
            R.problem_id AS problem_id,
            P.title AS problem_title,
            (SELECT s.de_id FROM sources s WHERE s.req_id = R.id) AS de,
            R.points AS clarified,
            D.t_blob AS question,
            D.t_blob AS answer,
            D.t_blob AS jury_message,
            A.id AS team_id,
            A.team_name$city_sql AS team_name,
            A.country AS country,
            COALESCE(E.ip, A.last_ip) AS last_ip,
            CA.id,
            R.contest_id
            FROM reqs R
            INNER JOIN problems P ON R.problem_id=P.id
            INNER JOIN accounts A ON R.account_id=A.id
            INNER JOIN contests C ON R.contest_id=C.id
            INNER JOIN contest_accounts CA ON CA.account_id=A.id AND CA.contest_id=R.contest_id
            LEFT JOIN events E ON E.id = R.id,
            dummy_table D
        ~,
        question => qq~
            2 AS rtype,
            Q.submit_time AS rank,
            Q.submit_time,
            Q.id AS id,
            CAST(NULL AS INTEGER) AS request_state,
            CAST(NULL AS INTEGER) AS failed_test,
            CAST(NULL AS INTEGER) AS problem_id,
            CAST(NULL AS VARCHAR(200)) AS problem_title,
            $no_de,
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
        message => qq~
            3 AS rtype,
            M.send_time AS rank,
            M.send_time AS submit_time,
            M.id AS id,
            CAST(NULL AS INTEGER) AS request_state,
            CAST(NULL AS INTEGER) AS failed_test,
            CAST(NULL AS INTEGER) AS problem_id,
            CAST(NULL AS VARCHAR(200)) AS problem_title,
            $no_de,
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
        broadcast => qq~
            4 AS rtype,
            M.send_time AS rank,
            M.send_time AS submit_time,
            M.id AS id,
            CAST(NULL AS INTEGER) AS request_state,
            CAST(NULL AS INTEGER) AS failed_test,
            CAST(NULL AS INTEGER) AS problem_id,
            CAST(NULL AS VARCHAR(200)) AS problem_title,
            $no_de,
            CAST(NULL AS INTEGER) AS clarified,
            D.t_blob AS question,
            D.t_blob AS answer,
            M.text AS jury_message,
            $dummy_account_block
            FROM messages M, dummy_table D
        ~,
        (map { +"contest_$contest_date_types[$_]" => qq~
            5 AS rtype,
            C.$contest_date_types[$_]_date AS rank,
            C.$contest_date_types[$_]_date AS submit_time,
            C.id AS id,
            C.is_official AS request_state,
            $_ AS failed_test,
            CAST(NULL AS INTEGER) AS problem_id,
            C.title AS problem_title,
            $no_de,
            CAST(NULL AS INTEGER) AS clarified,
            D.t_blob AS question,
            D.t_blob AS answer,
            D.t_blob AS jury_message,
            $dummy_account_block
            FROM contests C, dummy_table D
        ~ } 0 .. $#contest_date_types),
    );

    my $runs_filter = $s->{show_results} ? '' : ' AND 1 = 0';
    my $user_filter = url_param('uf') || '';
    my @user_ids = grep $_, map sprintf('%d', $_), split ',', $user_filter;
    my $events_filter = @user_ids ? 'AND (' . join(' OR ', map 'A.id = ?', @user_ids) . ')' : '';
    my @events_filter_params = @user_ids;

    my $contest_dates = '';
    if ($s->{show_contests})
    {
        my %extra_cond = (
            start => '',
            freeze => ' AND C.freeze_date < C.finish_date AND C.freeze_date > C.start_date',
            finish => '');
        my $hidden_cond = $is_root ? '' : ' AND C.is_hidden = 0';
        $contest_dates = join '', map qq~
                UNION
            SELECT
                $console_select{"contest_$_"}
                WHERE (C.${_}_date > CURRENT_TIMESTAMP - $day_count) AND
                    (C.${_}_date < CURRENT_TIMESTAMP)$extra_cond{$_}$hidden_cond~,
                    qw(start freeze finish);
    }

    my $broadcast = $s->{show_messages} ? qq~
            UNION
        SELECT
            $console_select{broadcast}
            WHERE (M.send_time > CURRENT_TIMESTAMP - $day_count) AND M.broadcast = 1~
        : '';
    my $submit_time_filter =
        '(R.submit_time BETWEEN C.start_date AND C.freeze_date OR CURRENT_TIMESTAMP > C.defreeze_date)';

    my $DEs = $is_team ? $dbh->selectall_hashref(q~
        SELECT id, description FROM default_de~, 'id') : {};
    my $pf = param('pf') || '';
    my $c;
    if ($is_jury)
    {
        my $jury_runs_filter = $is_root ? '' : ' AND C.id = ?';
        my $msg_filter = $is_root ? '' : ' AND CA.contest_id = ?';
        $msg_filter .= ' AND 1 = 0' unless $s->{show_messages};
        my @cid = $is_root ? () : ($cid);
        my $problem_filter = $pf ? ' AND P.id = ?' : '';
        my @pf_params = $pf ? ($pf) : ();
        $c = $dbh->prepare(qq~
            SELECT
                $console_select{run}
                WHERE R.submit_time > CURRENT_TIMESTAMP - $day_count
                $problem_filter$jury_runs_filter$events_filter$runs_filter
            UNION
            SELECT
                $console_select{question}
                FROM questions Q, contest_accounts CA, dummy_table D, accounts A
                WHERE (Q.submit_time > CURRENT_TIMESTAMP - $day_count) AND
                Q.account_id=CA.id AND A.id=CA.account_id$msg_filter
                $events_filter
            UNION
            SELECT
                $console_select{message}
                FROM messages M, contest_accounts CA, dummy_table D, accounts A
                WHERE (M.send_time > CURRENT_TIMESTAMP - $day_count) AND
                M.account_id = CA.id AND A.id = CA.account_id$msg_filter
                $events_filter
            $broadcast
            $contest_dates
            ORDER BY 2 DESC~);
        $c->execute(
            @pf_params,
            @cid, @events_filter_params,
            @cid, @events_filter_params,
            @cid, @events_filter_params);
    }
    elsif ($is_team)
    {
        $c = $dbh->prepare(qq~
            SELECT
                $console_select{run}
                WHERE (R.submit_time > CURRENT_TIMESTAMP - $day_count) AND
                    C.id=? AND CA.is_hidden=0 AND
                    (A.id=? OR $submit_time_filter)
                $events_filter$runs_filter
            UNION
            SELECT
                $console_select{question}
                FROM questions Q, contest_accounts CA, dummy_table D, accounts A
                WHERE (Q.submit_time > CURRENT_TIMESTAMP - $day_count) AND
                    Q.account_id=CA.id AND CA.contest_id=? AND CA.account_id=A.id AND A.id=?
            UNION
            SELECT
                $console_select{message}
                FROM messages M, contest_accounts CA, dummy_table D, accounts A
                WHERE (M.send_time > CURRENT_TIMESTAMP - $day_count) AND
                    M.account_id=CA.id AND CA.contest_id=? AND CA.account_id=A.id AND A.id=?
            $broadcast
            $contest_dates
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
                WHERE (R.submit_time > CURRENT_TIMESTAMP - $day_count) AND
                    R.contest_id=? AND CA.is_hidden=0 AND
                    ($submit_time_filter)
                    $events_filter$runs_filter
            $broadcast
            $contest_dates
            ORDER BY 2 DESC~);
        $c->execute($cid, @events_filter_params);
    }

    my $fetch_console_record = sub($)
    {
        my ($rtype, $rank, $submit_time, $id, $request_state, $failed_test,
            $problem_id, $problem_title, $de, $clarified, $question, $answer, $jury_message,
            $team_id, $team_name, $country_abbr, $last_ip, $caid, $contest_id
        ) = $_[0]->fetchrow_array
            or return ();

        $request_state = -1 unless defined $request_state;

        my ($country, $flag) = CATS::Countries::get_flag($country_abbr);
        my %st = state_to_display($request_state,
            # Security: During the contest, show teams only accepted/rejected
            # instead of specific results of other teams.
            $contest->{time_since_defreeze} <= 0 && !$is_jury &&
            (!$is_team || !$team_id || $team_id != $uid));
        return (
            country => $country,
            flag => $flag,
            is_submit_result =>     $rtype == 1,
            is_question =>          $rtype == 2,
            is_message =>           $rtype == 3,
            is_broadcast =>         $rtype == 4,
            is_contest =>           $rtype == 5,
            ($rtype == 5 ? (contest_date_type => $contest_date_types[$failed_test]) : ()),
            is_official =>          $request_state,
            # Hack: re-use 'clarified' field since it is relevant for questions only.
            points =>               $clarified,
            clarified =>            $clarified,
            href_details => (
                ($uid && $team_id && $uid == $team_id) ? url_f('run_details', rid => $id) : ''
            ),
            href_source => url_f('view_source', rid => $id),
            href_problems =>        url_function('problems', sid => $sid, cid => $id),
            ($is_jury && $privs->{moderate_messages} ? (
                href_delete_question => url_f('console', delete_question => $id),
                href_delete_message =>  url_f('console', delete_message => $id),
            ) : ()),
            href_answer_box =>      $is_jury ? url_f('answer_box', qid => $id) : undef,
            href_send_message_box =>$is_jury ? url_f('send_message_box', caid => $caid) : undef,
            'time' =>               $submit_time,
            time_iso =>             date_to_iso($submit_time),
            problem_id =>           $problem_id,
            problem_title =>        $problem_title,
            de =>                   $de,
            request_state =>        $request_state,
            request_state_text =>   scalar grep($st{$_}, keys %st), %st,
            failed_test =>          $failed_test,
            question_text =>        decode_utf8($question),
            answer_text =>          decode_utf8($answer),
            message_text =>         decode_utf8($jury_message),
            team_id =>              $team_id,
            team_name =>            $team_name,
            CATS::IP::linkify_ip(CATS::IP::filter_ip($last_ip)),
            id      =>              $id,
            contest_id =>           $contest_id,
        );
    };

    attach_listview(
        url_f('console'), $fetch_console_record, $c,
        { page_params => { uf => $user_filter, pf => $pf } });

    $c->finish;

    if ($is_team && !$settings->{hide_envelopes}) {
        my $cond =
            "WHERE account_id = ? AND state >= $cats::request_processed " .
            'AND received = 0 AND contest_id = ?';
        my $envelope_ids = $dbh->selectcol_arrayref(qq~
            SELECT id FROM reqs $cond~, undef,
            $uid, $cid
        );
        $t->param(envelopes => [
            map { href_envelope => url_f('envelope', rid => $_) }, @$envelope_ids ]);
        $dbh->commit; # Minimize deadlock chance.
        $dbh->do(qq~
            UPDATE reqs SET received = 1 $cond~, undef,
            $uid, $cid);
        $dbh->commit;
    }

    $t->param(
        href_my_events_only => url_f('console', uf => ($uid || get_anonymous_uid())),
        href_all_events => url_f('console', uf => 0),
        user_filter => $user_filter,
        is_jury => $is_jury,
        DEs => $DEs,
    );
}


sub select_all_reqs
{
    my ($extra_cond) = $_[0] || '';
    $dbh->selectall_arrayref(qq~
        SELECT
            R.id AS id, R.submit_time, R.state, R.failed_test,
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


sub xml_quote {
    my ($s) = @_;
    $s =~ s/</&lt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/&/&amp;/g;
    $s;
}

sub export
{
    $is_jury or return;
    init_template('console_export.xml.tt');
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
        $req->{s} = join '', map "<$_>" . xml_quote($req->{$_}) . "</$_>",
            grep defined $req->{$_}, keys %$req;
    }
    $t->param(reqs => $reqs);
}


sub graphs
{
    $is_jury or return;
    init_template('console_graphs.html.tt');
    my @codes = map { code => $_, selected => 1 }, @{$contest->used_problem_codes};
    my $steps_per_hour = (param('steps') || 1) + 0;
    my $accepted_only = param('accepted_only') || 0;
    $t->param(
        submenu => [ { href => url_f('console'), item => res_str(510) } ],
        codes => \@codes,
        href_graphs => url_f('console_graphs'),
        steps => $steps_per_hour,
        accepted_only => $accepted_only);
    param('do_graph') or return;

    my %selected_codes = map { $_ => 1 } param('selected_codes');
    $_->{selected} = $selected_codes{$_->{code}} || 0 for @codes;

    my $reqs = select_all_reqs($accepted_only ? " AND R.state = $cats::st_accepted" : '');
    @$reqs or return;
    my $init_graph = sub { (code => $_[0], by_time => []) };
    my $graphs = { all => { $init_graph->('all') } };
    for my $req (@$reqs)
    {
        $req->{code} && $req->{time_since_start} >= 0 && $selected_codes{$req->{code}} or next;
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
    $is_jury or return;
    my ($selection) = @_;
    my $count = 0;
    my @sanitized_runs = grep $_ ne '', split /\D+/, $selection;
    for (@sanitized_runs)
    {
        CATS::Request::enforce_state(request_id => $_, state => $cats::st_not_processed)
            and ++$count;
    }
    return $count;
}


sub delete_question
{
    my ($qid) = @_;
    $is_jury && $privs->{moderate_messages} or return;
    $dbh->do(q~DELETE FROM questions WHERE id = ?~, undef, $qid);
    $dbh->commit;
}


sub delete_message
{
    my ($mid) = @_;
    $is_jury && $privs->{moderate_messages} or return;
    $dbh->do(q~DELETE FROM messages WHERE id = ?~, undef, $mid);
    $dbh->commit;
}


sub console_frame
{
    init_console_template('console.html.tt');
    my $s = get_settings;
    if (grep defined param($_), qw(search filter visible)) {
        $s->{$_} = param($_) ? 1 : 0
            for qw(show_contests show_messages show_results);
    }

    my $question_text = param('question_text');
    my $selection = param('selection');

    if (my $qid = param('delete_question')) {
        delete_question($qid);
    }
    if (my $mid = param('delete_message')) {
        delete_message($mid);
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
        href_console_content => url_f('console_content', map { $_ => (url_param($_) || '') } qw(uf pf se page)),
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
        { href => url_f('console_export'), item => res_str(561) },
        { href => url_f('console_graphs'), item => res_str(563) },
    ]) if $is_jury;
}


sub content_frame
{
    console_content;
    return if param('json');
    my $cc = $t->output;
    init_template('console_iframe.html.tt');
    $t->param(console_content => $cc, is_team => $is_team);
}


1;
