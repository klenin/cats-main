package CATS::UI::Console;

use strict;
use warnings;

use Encode qw(decode_utf8);
use List::Util;

use CATS::Console;
use CATS::Contest::Participate qw(get_registered_contestant);
use CATS::Countries;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t $uid $user);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(auto_ext init_template url_f);
use CATS::Problem::Utils;
use CATS::Request;
use CATS::Settings qw($settings);
use CATS::Time;
use CATS::Utils qw(date_to_iso escape_xml url_function);
use CATS::Verdicts;
use CATS::Web qw(param url_param);

# This is called before init_template to display submitted question immediately.
sub send_question_to_jury {
    my ($question_text) = @_;

    $user->{is_participant} && defined $question_text && $question_text ne ''
        or return;
    length($question_text) <= 1000 or return res_str(1063);

    my ($previous_question_text) = $dbh->selectrow_array(q~
        SELECT question FROM questions
        WHERE account_id = ? ORDER BY submit_time DESC ROWS 1~, undef,
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

sub get_settings {
    my ($lv) = @_;
    my $s = $lv->settings;
    $s->{i_value} = param('i_value') // $s->{i_value} // 1;
    $s->{i_unit} = param('i_unit') || $s->{i_unit} || 'hours';
    $s->{show_results} = param('show_results') // $s->{show_results} // 1;
    $s->{show_messages} = param('show_messages') // $s->{show_messages} // 0;
    $s->{show_contests} = param('show_contests') // $s->{show_contests} // 0;
    $s;
}

sub init_console_template {
    my ($template_name) = @_;
    my $se = param('se') || '';
    $se = "_$se" if $se;
    CATS::ListView->new(
        name => "console$se", array_name => 'console', template => $template_name);
}

sub _decorate_rows {
    my ($data) = @_;
    my $contest_titles_sth;
    my $contest_titles = { $cid => $contest->{title} };

    for (@$data) {
        if (!exists $contest_titles->{$_->{contest_id}}) {
           $contest_titles_sth //= $dbh->prepare(q~
                SELECT title FROM contests WHERE id = ?~);
           $contest_titles_sth->execute($_->{contest_id});
           ($contest_titles->{$_->{contest_id}}) = $contest_titles_sth->fetchrow_array;
           $contest_titles_sth->finish;
        }
        $_->{contest_title} = $contest_titles->{$_->{contest_id}};
    }
}

sub console_content {
    my $selection = param('selection');

    my $lv = init_console_template(auto_ext('console_content'));

    retest_submissions($selection, param('by_reference')) if defined param('retest') and $selection;
    group_submissions($selection, param('by_reference')) if defined param('create_group') && $selection;

    my $s = get_settings($lv);

    if (grep defined param($_), qw(search filter visible)) {
        $s->{$_} = param($_) ? 1 : 0
            for qw(show_contests show_messages show_results);
    }

    $t->param($_ => $s->{$_}) for qw(show_contests show_messages show_results i_value);

    my $DEs = $uid ? $dbh->selectall_hashref(q~
        SELECT id, code, description FROM default_de~, 'id') : {};

    # Optimization: Only display problem codes from the currect contest to avoid another JOIN.
    my $problem_codes = !$contest->is_practice ? $dbh->selectall_hashref(q~
        SELECT problem_id, code FROM contest_problems WHERE contest_id = ?~, 'problem_id', undef, $cid) : {};

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
        CA.is_jury
    ) ]);

    my $de_select = q~
        (SELECT %s FROM sources S INNER JOIN default_de DE ON DE.id = S.de_id WHERE S.req_id = R.id)~;

    $lv->define_db_searches({
        de_code => sprintf($de_select, 'DE.code'),
        de_name => sprintf($de_select, 'DE.description'),
        run_method => 'P.run_method',
        code => '(SELECT CP.code FROM contest_problems CP WHERE CP.contest_id = C.id AND CP.problem_id = P.id)',
        next => q~COALESCE((
            SELECT R1.id FROM reqs R1
            WHERE
                R1.contest_id = R.contest_id AND
                R1.problem_id = R.problem_id AND
                R1.account_id = R.account_id AND
                R1.id > R.id
            ROWS 1), 0)~,
        tag => q~COALESCE(R.tag, '')~,
        contest_title => 'C.title',
        account_id => 'A.id',
        contest_id => 1, # Handled manually.
    });

    $lv->define_enums({
        state => $CATS::Verdicts::name_to_state,
        run_method => CATS::Problem::Utils::run_method_enum,
        contest_id => { this => $cid },
        account_id => { this => $uid },
    });

    my $user_filter = url_param('uf') || '';
    my $sth = CATS::Console::build_query($s, $lv, $user_filter);

    my $fetch_console_record = sub {
        my ($rtype, $rank, $submit_time, $id, $request_state, $failed_test,
            $problem_id, $problem_title, $de, $clarified, $question, $answer, $jury_message,
            $team_id, $team_name, $country_abbr, $last_ip, $caid, $contest_id
        ) = $_[0]->fetchrow_array
            or return ();

        $request_state = -1 unless defined $request_state;

        my ($country, $flag) = CATS::Countries::get_flag($country_abbr);

        # Security: During the contest, show teams only accepted/rejected
        # instead of specific results of other teams.
        my $hide_verdict =
            $contest->{time_since_defreeze} <= 0 && !$is_jury &&
            (!$user->{is_participant} || !$team_id || $team_id != $uid);
        my $true_short_state = $CATS::Verdicts::state_to_name->{$request_state} || '';
        my $short_state = $hide_verdict ? $CATS::Verdicts::hidden_verdicts->{$true_short_state} : $true_short_state;
        my $show_details = $is_jury || $uid && $team_id && $uid == $team_id;

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
            href_problems =>        url_function('problems', sid => $sid, cid => $id),
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
            problem_title =>        $problem_title,
            de =>                   $de,
            request_state =>        $request_state,
            short_state =>          $short_state,
            failed_test =>          ($hide_verdict ? '' : $failed_test),
            question_text =>        decode_utf8($question),
            answer_text =>          decode_utf8($answer),
            message_text =>         decode_utf8($jury_message),
            team_id =>              $team_id,
            team_name =>            $team_name,
            CATS::IP::linkify_ip($last_ip),
            id      =>              $id,
            contest_id =>           $contest_id,
        );
    };

    $lv->attach(
        url_f('console'), ($sth ? $fetch_console_record : sub { () }), $sth,
        { page_params => { se => param('se') || undef, uf => $user_filter || undef } });

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

    $t->param(
        DEs => $DEs,
    );
}

sub select_all_reqs {
    $dbh->selectall_arrayref(qq~
        SELECT
            R.id AS id, R.submit_time, R.state, R.failed_test,
            R.submit_time - $CATS::Time::contest_start_offset_sql AS time_since_start,
            CP.code, P.title AS problem_title,
            A.id AS team_id, A.team_name, A.last_ip,
            CA.is_remote, CA.is_ooc
        FROM
            reqs R
            INNER JOIN problems P ON R.problem_id = P.id
            INNER JOIN contest_accounts CA ON CA.contest_id = R.contest_id AND CA.account_id = R.account_id
            INNER JOIN contests C ON R.contest_id = C.id
            INNER JOIN contest_problems CP ON R.contest_id = CP.contest_id AND CP.problem_id = R.problem_id
            INNER JOIN accounts A ON CA.account_id = A.id
            LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
        WHERE
            R.contest_id = ? AND CA.is_hidden = 0 AND CA.is_virtual = 0 AND R.submit_time > C.start_date
        ORDER BY R.submit_time ASC~, { Slice => {} },
        $cid);
}

sub export_frame {
    $is_jury or return;
    # Legacy field, new consumers should use short_state.
    my %state_to_display = (
        $cats::st_wrong_answer => 'wrong_answer',
        $cats::st_presentation_error => 'presentation_error',
        $cats::st_time_limit_exceeded => 'time_limit_exceeded',
        $cats::st_memory_limit_exceeded => 'memory_limit_exceeded',
        $cats::st_memory_limit_exceeded => 'write_limit_exceeded',
        $cats::st_runtime_error => 'runtime_error',
        $cats::st_compilation_error => 'compilation_error',
        $cats::st_idleness_limit_exceeded => 'idleness_limit_exceeded',
        $cats::st_manually_rejected => 'manually_rejected',
        $cats::st_not_processed => 'not_processed',
        $cats::st_unhandled_error => 'unhandled_error',
        $cats::st_install_processing => 'install_processing',
        $cats::st_testing => 'testing',
        $cats::st_awaiting_verification => 'awaiting_verification',
        $cats::st_accepted => 'accepted',
        $cats::st_security_violation => 'security_violation',
        $cats::st_ignore_submit => 'ignore_submit',
    );
    init_template('console_export.xml.tt');
    my $reqs = select_all_reqs;
    for my $req (@$reqs) {
        $req->{submit_time} =~ s/\s+$//;
        $req->{short_state} = $CATS::Verdicts::state_to_name->{$req->{state}};
        $req->{state} = $state_to_display{$req->{state}};
        $req->{s} = join '', map "<$_>" . escape_xml($req->{$_}) . "</$_>",
            sort grep defined $req->{$_}, keys %$req;
    }
    $t->param(reqs => $reqs);
}

sub graphs_frame {
    $is_jury or return;
    init_template('console_graphs.html.tt');

    my $reqs = select_all_reqs;
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

sub retest_submissions {
    $is_jury or return;
    my ($selection, $by_reference) = @_;
    my $count = 0;
    my @sanitized_runs = grep $_ ne '', split /\D+/, $selection;
    if ($by_reference) {
        $count = @{CATS::Request::clone(\@sanitized_runs, undef, $uid)};
    } else {
        for (@sanitized_runs) {
            CATS::Request::enforce_state($_, { state => $cats::st_not_processed, judge_id => undef })
                and ++$count;
        }
    }
    $dbh->commit;
    return $count;
}

sub group_submissions {
    $is_root or return;
    my ($selection, $by_reference) = @_;
    my $count = 0;
    my @sanitized_runs = grep $_ ne '', split /\D+/, $selection;
    CATS::Request::create_group(
        ($by_reference ? CATS::Request::clone(\@sanitized_runs, undef, $uid, { state => $cats::st_ignore_submit }) : \@sanitized_runs),
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

    console_content;
    return if param('json');
    CATS::Time::prepare_server_time;
    my $lvparams = $t->{vars};
    my $cc = $t->output;
    my $user_filter = url_param('uf') || '';

    my $lv = init_console_template('console.html.tt');

    $t->param($_ => $lvparams->{$_}) for qw(
        i_units i_unit i_values i_value display_rows rows
        page pages search show_contests show_messages show_results
        href_lv_action href_next_pages href_prev_pages search_hints search_enums
    );
    $t->param(
        href_console_content =>
            url_f('console_content', noredir => 1, map { $_ => (url_param($_) || '') } qw(uf se page)),
        selection => scalar(param('selection')),
        href_my_events_only =>
            url_f('console', uf => ($uid || $user->{anonymous_id}), se => param('se') || undef),
        href_all_events => url_f('console', uf => 0, se => param('se') || undef),
        href_view_source => url_f('view_source'),
        href_run_details => url_f('run_details'),
        href_run_log => url_f('run_log'),
        href_diff => url_f('diff_runs'),
        title_suffix => res_str(510),
        initial_content => $cc,
        autoupdate => $lv->settings->{autoupdate} // 30,
        ajax_error_msg => res_str(1151),
        user_filter => $user_filter,
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

sub content_frame { console_content }

1;
