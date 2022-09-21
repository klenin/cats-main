package CATS::UI::Messages;

use strict;
use warnings;

use Encode;

use CATS::Config;
use CATS::DB qw(:DEFAULT $db);
use CATS::Globals qw($cid $t $is_jury $uid $user);
use CATS::Messages qw(res_str);
use CATS::Output qw(init_template url_f);
use CATS::Verdicts;
use CATS::User;
use CATS::Utils;

sub _get_groups {
    my ($account_id, $contest_id) = @_;

    my $groups = $dbh->selectcol_arrayref(q~
        SELECT AG.name FROM acc_groups AG
        INNER JOIN acc_group_accounts AGA ON AGA.acc_group_id = AG.id AND AGA.is_hidden = 0
        INNER JOIN acc_group_contests AGC ON AGC.acc_group_id = AG.id
        WHERE AGA.account_id = ? AND AGC.contest_id = ?
        ORDER BY AG.name~, undef,
        $account_id, $contest_id);
}

sub send_message_box_frame {
    my ($p) = @_;
    init_template($p, 'send_message_box.html.tt');
    $is_jury or return;

    my $caid = $p->{caid} or return;

    my ($account_id, $contest_id, $team_name, $site) = $dbh->selectrow_array(q~
        SELECT A.id, CA.contest_id, A.team_name, S.name
        FROM accounts A INNER JOIN contest_accounts CA ON CA.account_id = A.id
        LEFT JOIN sites S ON S.id = CA.site_id
        WHERE CA.id = ?~, undef,
        $caid) or return;

    $t->param(
        team => $team_name,
        site => $site,
        groups => _get_groups($account_id, $contest_id),
        title_suffix => res_str(567, $team_name),
    );

    $p->{send} or return;
    my $message_text = $p->{message_text} or return;
    CATS::User::send_message(user_set => [ $caid ], message => $message_text, contest_id => $cid);
    $dbh->commit;
    $t->param(sent => 1);
}

sub _get_question {
    my ($p) = @_;
    my $r = $dbh->selectrow_hashref(q~
        SELECT
            Q.account_id AS caid, CA.account_id AS aid, A.login, A.team_name,
            S.name AS site_name,
            Q.submit_time, Q.question, Q.clarified, Q.answer, C.title, CA.contest_id
        FROM questions Q
        INNER JOIN contest_accounts CA ON CA.id = Q.account_id
        INNER JOIN accounts A ON A.id = CA.account_id
        INNER JOIN contests C ON C.id = CA.contest_id
        LEFT JOIN sites S ON S.id = CA.site_id
        WHERE Q.id = ?~, { Slice => {} },
        $p->{qid}) or return;
    # BLOBs are not auto-decoded.
    $_ = Encode::decode_utf8($_) for @$r{qw(question answer)};
    $r->{submit_time} = $db->format_date($r->{submit_time});
    $r;
}

sub answer_box_frame {
    my ($p) = @_;
    init_template($p, 'answer_box.html.tt');
    $is_jury && $p->{qid} or return;

    my $r = _get_question($p) or return;
    $user->{is_root} || $r->{contest_id} == $cid or return;

    $t->param(
        participant_name => $r->{team_name},
        site => $r->{site_name},
        title_suffix => res_str(566) . " $r->{team_name}", contest_title => $r->{title});

    if ($p->{clarify} && (my $ans = $p->{answer_text} // '') ne '') {
        $r->{answer} = $user->privs->{moderate_messages} ? $ans : ($r->{answer} // '') . " $ans";
        my $s = $dbh->prepare(q~
            UPDATE questions
            SET clarification_time = CURRENT_TIMESTAMP, answer = ?, received = 0, clarified = 1
            WHERE id = ?~);
        $db->bind_blob($s, 1, $r->{answer});
        $s->bind_param(2, $p->{qid});
        $s->execute;
        $dbh->commit;
        $t->param(clarified => 1);
    }
    else {
        $t->param(
            groups => _get_groups($r->{aid}, $r->{contest_id}),
            submit_time => $r->{submit_time},
            question_text => $r->{question},
            answer => $r->{answer});
    }
}

sub envelope_frame {
    my ($p) = @_;
    init_template($p, 'envelope.html.tt');

    $user->{is_participant} && $p->{rid} or return;

    my $r = $dbh->selectrow_hashref(q~
        SELECT
            R.submit_time, R.test_time, R.state, R.failed_test, R.account_id,
            A.team_name, C.title, P.title AS problem_name
        FROM reqs R
            INNER JOIN contests C ON C.id = R.contest_id
            INNER JOIN accounts A ON A.id = R.account_id
            INNER JOIN problems P ON P.id = R.problem_id
        WHERE R.id = ? AND R.account_id = ?~, { Slice => {} },
        $p->{rid}, $uid) or return;
    $r->{$_} = $db->format_date($r->{$_}) for qw(submit_time test_time);
    $t->param(%$r, verdict => $CATS::Verdicts::state_to_name->{$r->{state}});
}

sub questions_api {
    my ($p) = @_;
    $is_jury or return $p->print_json({});
    my $questions = $dbh->selectall_arrayref(q~
        SELECT
            CA.contest_id, CA.account_id, A.team_name, S.name AS site_name,
            Q.id, Q.submit_time, Q.clarification_time, Q.clarified, Q.question, Q.answer
        FROM questions Q
        INNER JOIN contest_accounts CA ON CA.id = Q.account_id
        INNER JOIN accounts A ON A.id = CA.account_id
        LEFT JOIN sites S ON S.id = CA.site_id
        WHERE CA.contest_id = ? AND Q.clarified = ?~, { Slice => {} },
        $cid, $p->{clarified} ? 1 : 0);
    for my $q (@$questions) {
        $q->{$_} = $db->format_date($q->{$_}) for qw(submit_time clarification_time);
        $q->{$_} = Encode::decode_utf8($q->{$_}) for qw(answer question);
        $q->{href_console} = CATS::Utils::absolute_url_function(
            f => 'console', se => 'user_stats',
            uf => $q->{account_id}, i_value => -1, search => 'contest_id=this',
            cid => $cid, sid => 'z');
    }
    $p->print_json({ questions => $questions });
}

sub answer_api {
    my ($p) = @_;
    $is_jury && $user->privs->{moderate_messages} && $p->{qid} && ($p->{answer} // '') ne ''
        or return $p->print_json({});

    my $r = _get_question($p) or return $p->print_json({});
    $r->{contest_id} == $cid or return $p->print_json({});

    my $ans = Encode::decode_utf8($p->{answer});
    $dbh->do(q~
        UPDATE questions
        SET clarification_time = CURRENT_TIMESTAMP, answer = ?, received = 0, clarified = 1
        WHERE id = ?~, undef,
        $r->{answer} ? "$r->{answer} $ans" : $ans, $p->{qid});
    $dbh->commit;
    $p->print_json({ result => 'ok', id => $p->{qid} });
}

1;
