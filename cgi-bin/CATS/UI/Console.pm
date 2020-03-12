package CATS::UI::Console;

use strict;
use warnings;

use Encode;
use List::Util;

use CATS::Console;
use CATS::Constants;
use CATS::Contest::Participate qw(get_registered_contestant);
use CATS::Countries;
use CATS::DB qw(:DEFAULT $KW_LIMIT);
use CATS::Globals qw($cid $contest $is_jury $is_root $t $uid $user);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f url_f_cid);
use CATS::Problem::Utils;
use CATS::RankTable;
use CATS::Request;
use CATS::Settings qw($settings);
use CATS::Time;
use CATS::Utils qw(date_to_iso);
use CATS::Verdicts;

# This is called before init_template to display submitted question immediately.
sub send_question_to_jury {
    my ($question_text) = @_;

    $user->{is_participant} && defined $question_text && $question_text ne ''
        or return;
    length($question_text) <= 1000 or return res_str(1063);

    my ($previous_question_text) = $dbh->selectrow_array(qq~
        SELECT question FROM questions
        WHERE account_id = ? ORDER BY submit_time DESC $KW_LIMIT 1~, undef,
        $user->{ca_id});
    ($previous_question_text || '') ne $question_text or return msg(1061);

    my $s = $dbh->prepare(q~
        INSERT INTO questions(id, account_id, submit_time, question, received, clarified)
        VALUES (?, ?, CURRENT_TIMESTAMP, ?, 0, 0)~);
    $s->bind_param(1, new_id);
    $s->bind_param(2, $user->{ca_id});
    $s->bind_param(3, $question_text, { ora_type => 113 } );
    $s->execute;
    $s->finish;
    $dbh->commit;
    msg(1062);
}

sub _get_settings {
    my ($p, $lv) = @_;
    my $s = $lv->settings;
    $s->{i_value} = $p->{i_value} // $s->{i_value} // 1;
    $s->{i_unit} = $p->{i_unit} || $s->{i_unit} || 'hours';
    if ($is_jury) {
        $s->{$_} = $lv->submitted ? ($p->{$_} ? 1 : 0) : ($p->{$_} // $s->{$_} // 1)
            for qw(show_contests show_messages show_results);
    }
    $s;
}

sub _init_console_template {
    my ($p, $template_name) = @_;
    my $se = $p->{se} ? "_$p->{se}" : '';
    init_template($p, $template_name);
    CATS::ListView->new(
        web => $p, name => "console$se", array_name => 'console', url => url_f('console'));
}

sub _decorate_rows {
    my ($data) = @_;
    my $contest_titles_sth;
    my $contest_titles = { $cid => $contest->{title} };

    my $DEs = $uid ? $dbh->selectall_hashref(q~
        SELECT id, code, description FROM default_de~, 'id') : {};

    for (@$data) {
        if (my $c = $_->{contest_id}) {
            if (!exists $contest_titles->{$c}) {
               $contest_titles_sth //= $dbh->prepare(q~
                    SELECT title FROM contests WHERE id = ?~);
               $contest_titles_sth->execute($c);
               ($contest_titles->{$c}) = $contest_titles_sth->fetchrow_array;
               $contest_titles_sth->finish;
            }
            $_->{contest_title} = $contest_titles->{$c};
        }
        $_->{de} = $DEs->{$_->{de_id}} if $_->{de_id};
    }
}

sub _shortened_team_name {
    my ($team_name) = @_;
    $team_name && length($team_name) > 50 ?
        (team_name => substr($team_name, 0, 50) . "\x{2026}", team_name_full => $team_name) :
        (team_name => $team_name);
}

sub _console_content {
    my ($p) = @_;

    my $lv = _init_console_template($p, 'console_content');

    if (@{$p->{selection}}) {
        _retest_submissions($p->{selection}, $p->{by_reference}) if $p->{retest};
        _group_submissions($p->{selection}, $p->{by_reference}) if $p->{create_group};
    }

    my $s = _get_settings($p, $lv);

    $t->param($_ => $s->{$_}) for qw(show_contests show_messages show_results i_value);

    # Optimization: Only display problem codes from the currect contest to avoid another JOIN.
    my $problem_codes = !$contest->is_practice ? $dbh->selectall_hashref(q~
        SELECT problem_id, code FROM contest_problems WHERE contest_id = ?~, 'problem_id', undef, $cid) : {};

    $lv->default_sort(0)->define_columns([
        { caption => res_str(654), col => 'Cy' },
        { caption => res_str(632), col => 'Tm' },
        { caption => res_str(641), col => 'De' },
        { caption => res_str(671), col => 'Ip' },
    ]);
    $lv->define_db_searches([ qw(
        R.submit_time
        R.id
        R.state
        R.failed_test
        R.problem_id
        R.points
        R.judge_id
        R.elements_count
        P.title
        A.team_name
        A.city
        A.login
        CA.is_jury
        CA.site_id
    ) ]);

    my $de_select = q~
        (SELECT %s FROM sources S INNER JOIN default_de DE ON DE.id = S.de_id WHERE S.req_id = R.id)~;
    my $same_contest_problem_account = q~
        R1.contest_id = R.contest_id AND
        R1.problem_id = R.problem_id AND
        R1.account_id = R.account_id AND~;
    my $src_prefix_len = 2000;
    my $from_src = sub { "(SELECT $_[0] FROM sources S WHERE S.req_id = R.id)" };

    $lv->define_db_searches({
        de_code => sprintf($de_select, 'DE.code'),
        de_name => sprintf($de_select, 'DE.description'),
        run_method => 'P.run_method',
        last_ip => 'COALESCE(E.ip, A.last_ip)',
        code => q~(
            SELECT CP.code FROM contest_problems CP
            WHERE CP.contest_id = C.id AND CP.problem_id = P.id)~,
        source => $from_src->(
            "CAST(SUBSTRING(S.src FROM 1 FOR $src_prefix_len) AS VARCHAR($src_prefix_len))"),
        source_length => $from_src->('OCTET_LENGTH(S.src)'),
        next => qq~COALESCE((
            SELECT R1.id FROM reqs R1
            WHERE $same_contest_problem_account R1.id > R.id
            $KW_LIMIT 1), 0)~,
        tag => q~COALESCE(R.tag, '')~,
        contest_title => 'C.title',
        account_id => 'A.id',
        contest_id => 1, # Handled manually.
        submit_year => 'EXTRACT(YEAR FROM R.submit_time)',
        submit_month => 'EXTRACT(MONTH FROM R.submit_time)',
        submit_day => 'EXTRACT(DAY FROM R.submit_time)',
        jobs => '(SELECT COUNT(*) FROM jobs J WHERE J.req_id = R.id)',
        jobs_failed => qq~(
            SELECT COUNT(*) FROM jobs J WHERE J.req_id = R.id AND J.state = $cats::job_st_failed)~,
        jobs_queue => q~
            (SELECT COUNT(*)
            FROM jobs J INNER JOIN jobs_queue JQ ON J.id = JQ.id
            WHERE J.req_id = R.id)~,
        judge_name => '(SELECT JD.nick FROM judges JD WHERE JD.id = R.judge_id)',
        cp_id => q~(
            SELECT CP.id FROM contest_problems CP
            WHERE CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id)~,
        ($uid ? (can_see_reqs => qq~(
            SELECT RL.from_ok * RL.to_ok FROM relations RL
            WHERE RL.from_id = $uid AND RL.to_id = R.account_id)~) : ()),
        problem_accepted => qq~(
            SELECT COUNT(*) FROM reqs R1
            WHERE $same_contest_problem_account R1.state = $cats::st_accepted)~,
        problem_solved => qq~(
            SELECT COUNT(*) FROM reqs R1
            WHERE $same_contest_problem_account
                R1.state = $cats::st_accepted AND R1.points = CP.max_points)~,
    });

    $lv->define_enums({
        state => $CATS::Verdicts::name_to_state,
        run_method => CATS::Problem::Utils::run_method_enum,
        contest_id => { this => $cid },
        account_id => { this => $uid },
    });

    my $tested_on_sql = q~
        SELECT 1 FROM req_details RD WHERE RD.req_id = R.id AND RD.test_rank = ?~;
    $lv->define_subqueries({
        tested_on => { sq => qq~EXISTS ($tested_on_sql)~, m => 1199, t => undef },
        not_tested_on => { sq => qq~NOT EXISTS ($tested_on_sql)~, m => 1200, t => undef },
    });

    my $max_points_cond = $contest->{rules} ? ' AND R.points = CP.max_points' : '';
    my $solved = $contest->{show_all_for_solved} && $uid && !$is_jury ? $dbh->selectall_hashref(qq~
        SELECT CP.problem_id
        FROM contest_problems CP
        WHERE CP.contest_id = ? AND CP.status < $cats::problem_st_hidden AND EXISTS (
            SELECT * FROM reqs R
            WHERE R.account_id = ? AND R.contest_id = CP.contest_id AND R.problem_id = CP.problem_id AND
                R.state = $cats::st_accepted$max_points_cond
        )~, 'problem_id', undef,
        $cid, $uid) : {};

    my $can_see = $uid && !$is_jury ? CATS::Request::can_see_by_relation($uid) : {};

    my $uf = $is_jury || $contest->{show_all_results} ? $p->{uf} : [ $uid // -1 ];
    my $sth = CATS::Console::build_query($s, $lv, $uf);

    my $fetch_console_record = sub {
        my ($rtype, $rank, $submit_time, $id, $request_state, $failed_test,
            $problem_id, $elements_count, $problem_title,
            $de_id, $time_used, $clarified, $question, $answer, $jury_message,
            $team_id, $team_name, $country_abbr, $last_ip, $caid, $site_id, $contest_id
        ) = $_[0]->fetchrow_array
            or return ();

        $request_state = -1 unless defined $request_state;

        my ($country, $flag) = CATS::Countries::get_flag($country_abbr);

        # Security: During the contest, show teams only accepted/rejected
        # instead of specific results of other teams.
        my $hide_verdict =
            $contest->{time_since_defreeze} <= 0 && !$is_jury &&
            (!$user->{is_participant} || !$team_id || $team_id != ($uid // 0));
        my $true_short_state = $CATS::Verdicts::state_to_name->{$request_state} || '';
        my $short_state =
            $hide_verdict ? $CATS::Verdicts::hidden_verdicts_others->{$true_short_state} :
            CATS::Verdicts::hide_verdict_self($is_jury, $true_short_state);

        my $show_details =
            $is_jury || $uid && $team_id && $uid == $team_id ||
            ($contest->{time_since_pub_reqs} // 0) > 0 ||
            $team_id && $can_see->{$team_id} ||
            # $user->{is_site_org} && (!$user->{site_id} || $user->{site_id} == ($site_id // 0)) ||
            $problem_id && $solved->{$problem_id};

        return (
            country => $country,
            flag => $flag,
            is_submit_result =>     $rtype == 1,
            is_question =>          $rtype == 2,
            is_message =>           $rtype == 3,
            is_broadcast =>         $rtype == 4,
            is_contest =>           $rtype == 5,
            ($rtype == 5 ? (contest_date_type => $CATS::Console::contest_date_types[$failed_test]) : ()),
            is_official =>          $request_state,
            # Hack: re-use 'clarified' field since it is relevant for questions only.
            points =>               $clarified,
            clarified =>            $clarified,
            (($contest_id // 0) == $cid && $problem_id ? (code => $problem_codes->{$problem_id}->{code}) : ()),
            href_details =>         ($show_details ? url_f('run_details', rid => $id) : undef),
            href_source =>          ($show_details ? url_f('view_source', rid => $id) : undef),
            href_problems =>        url_f_cid('problems', cid => $id),
            ($is_jury && $user->privs->{moderate_messages} ? (
                href_delete_question => url_f('console', delete_question => $id),
                href_delete_message =>  url_f('console', delete_message => $id),
            ) : ()),
            href_answer_box =>
                $is_jury && (!$clarified || $user->privs->{moderate_messages}) ?
                url_f('answer_box', qid => $id) : undef,
            href_send_message_box =>
                ($is_jury && $caid ? url_f('send_message_box', caid => $caid) : undef),
            'time' =>               $submit_time,
            time_iso =>             date_to_iso($submit_time),
            problem_id =>           $problem_id,
            elements_count =>       $elements_count,
            problem_title =>        $problem_title,
            de_id =>                $de_id,
            time_used =>            $time_used && sprintf('%.1f', $time_used),
            request_state =>        $request_state,
            short_state =>          $short_state,
            failed_test =>          ($hide_verdict ? '' : $failed_test),
            question_text =>        Encode::decode_utf8($question),
            answer_text =>          Encode::decode_utf8($answer),
            message_text =>         $jury_message,
            team_id =>              $team_id,
            _shortened_team_name($team_name),
            CATS::IP::linkify_ip($last_ip),
            id      =>              $id,
            contest_id =>           $contest_id,
        );
    };

    $lv->attach(
        ($sth ? $fetch_console_record : sub { () }), $sth,
        { page_params => { se => $p->{se}, uf => join(',', @{$p->{uf}}) || undef } });

    $sth->finish if $sth;

    _decorate_rows($lv->visible_data);

    if ($uid && $user->{is_participant} && !$settings->{hide_envelopes}) {
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
}

sub export_frame {
    my ($p) = @_;
    $is_jury or return;
    init_template($p, 'console_export.xml.tt');
    $t->param(reqs => CATS::Console::export($cid));
}

sub graphs_frame {
    my ($p) = @_;
    $is_jury or return;
    init_template($p, 'console_graphs.html.tt');

    my $reqs = CATS::Console::select_all_reqs($cid);
    my $n2s = $CATS::Verdicts::name_to_state;
    my $used_verdicts = {};

    for my $r (@$reqs) {
        $r->{minutes} = int($r->{time_since_start} * 24 * 60 + 0.5);
        $r->{verdict} = $CATS::Verdicts::state_to_name->{$r->{state}};
        $used_verdicts->{$r->{verdict}} = 1;
    }
    $t->param(
        reqs => $reqs,
        codes => $contest->used_problem_codes,
        verdicts => [ sort{ $n2s->{$a} <=> $n2s->{$b} } keys %$used_verdicts ],
        submenu => [ { href => url_f('console'), item => res_str(510) } ],
    );
}

sub _retest_submissions {
    my ($selection, $by_reference) = @_;
    $is_jury or return;
    my $count = 0;
    if ($by_reference) {
        $count = @{CATS::Request::clone($selection, undef, $uid)};
    } else {
        my %affected_contests;
        my $contest_sth = $dbh->prepare(q~
            SELECT contest_id FROM reqs WHERE id = ?~);
        for (@$selection) {
            $contest_sth->execute($_);
            my ($contest_id) = $contest_sth->fetchrow_array;
            $contest_sth->finish;
            $contest_id && ($contest_id == $cid || $is_root) && CATS::Request::retest($_) or next;
            $affected_contests{$contest_id} = 1;
            ++$count;
        }
        CATS::RankTable::remove_cache($_) for keys %affected_contests;
    }

    $dbh->commit;
    msg(1128, $count);
}

sub _group_submissions {
    $is_root or return;
    my ($selection, $by_reference) = @_;
    my $count = 0;
    CATS::Request::create_group(
        ($by_reference ?
            CATS::Request::clone($selection, undef, $uid, { state => $cats::st_ignore_submit }) :
            $selection),
        $uid, { state => $cats::st_not_processed, judge_id => undef }) or return;
    $dbh->commit;
}

sub delete_question {
    my ($qid) = @_;
    $is_jury && $user->privs->{moderate_messages} or return;
    $dbh->do(q~
        DELETE FROM questions WHERE id = ?~, undef,
        $qid);
    $dbh->commit;
}

sub delete_message {
    my ($mid) = @_;
    $is_jury && $user->privs->{moderate_messages} or return;
    $dbh->do(q~
        DELETE FROM messages WHERE id = ?~, undef,
        $mid);
    $dbh->commit;
}

sub console_frame {
    my ($p) = @_;

    delete_question($p->{delete_question}) if $p->{delete_question};
    delete_message($p->{delete_message}) if $p->{delete_message};
    send_question_to_jury($p->{question_text}) if $p->{send_question};

    _console_content($p);
    return if $p->{json};
    CATS::Time::prepare_server_time;
    my $lvparams = $t->{vars};
    my $cc = $t->output;

    my $lv = _init_console_template($p, 'console.html.tt');

    $t->param($_ => $lvparams->{$_}) for qw(
        i_units i_unit i_values i_value display_rows rows
        page pages search show_contests show_messages show_results
        href_lv_action href_next_pages href_prev_pages search_hints search_enums
        can_change_cols visible_cols col_defs
    );
    $t->param(
        href_console_content =>
            url_f('console_content', noredir => 1, uf => join(',', @{$p->{uf}}) || undef,
            map { $_ => $p->{$_} } qw(se page)),
        selection => join(',', @{$p->{selection}}),
        href_my_events_only =>
            url_f('console', uf => ($uid || $user->{anonymous_id}), se => $p->{se}),
        href_all_events => url_f('console', se => $p->{se}),
        href_view_source => url_f('view_source'),
        href_run_details => url_f('run_details'),
        href_run_log => url_f('run_log'),
        href_diff => url_f('diff_runs'),
        title_suffix => res_str(510),
        initial_content => $cc,
        autoupdate => $lv->settings->{autoupdate} // 30,
        ajax_error_msg => res_str(1151),
        user_filter => scalar(@{$p->{uf}}),
    );
    my %all_types = (show_contests => 1, show_messages => 1, show_results => 1);
    $t->param(submenu => [
        { href => url_f('console_export'), item => res_str(561) },
        { href => url_f('console_graphs'), item => res_str(563) },
        { href => url_f('console', search => '',
            ($is_root ? (i_value => 1) : ()), %all_types), item => res_str(558) },
        ($is_root ? (
            { href => url_f('console', search => 'contest_id=this',
                i_value=> -1, %all_types), item => res_str(585) },
        ) : ()),
    ]) if $is_jury;
}

sub console_content_frame { _console_content(@_) }

1;
