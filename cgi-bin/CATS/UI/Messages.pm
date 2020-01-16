package CATS::UI::Messages;

use strict;
use warnings;

use Encode;

use CATS::DB;
use CATS::Globals qw($cid $t $is_jury $uid $user);
use CATS::Messages qw(res_str);
use CATS::Output qw(init_template);
use CATS::Verdicts;
use CATS::User;

sub send_message_box_frame {
    my ($p) = @_;
    init_template($p, 'send_message_box.html.tt');
    $is_jury or return;

    my $caid = $p->{caid} or return;

    my $team_name = $dbh->selectrow_array(q~
        SELECT A.team_name
        FROM accounts A INNER JOIN contest_accounts CA ON CA.account_id = A.id
        WHERE CA.id = ?~, undef,
        $caid) or return;

    $t->param(team => $team_name, title_suffix => res_str(567, $team_name));

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
            Q.submit_time, Q.question, Q.clarified, Q.answer, C.title, CA.contest_id
        FROM questions Q
        INNER JOIN contest_accounts CA ON CA.id = Q.account_id
        INNER JOIN accounts A ON A.id = CA.account_id
        INNER JOIN contests C ON C.id = CA.contest_id
        WHERE Q.id = ?~, { Slice => {} },
        $p->{qid}) or return;
    # BLOBs are not auto-decoded.
    $_ = Encode::decode_utf8($_) for @$r{qw(question answer)};
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
        title_suffix => res_str(566), contest_title => $r->{title});

    if ($p->{clarify} && (my $ans = Encode::decode_utf8($p->{answer_text}) // '') ne '') {
        $r->{answer} = $user->privs->{moderate_messages} ? $ans : ($r->{answer} // '') . " $ans";
        my $s = $dbh->prepare(q~
            UPDATE questions
            SET clarification_time = CURRENT_TIMESTAMP, answer = ?, received = 0, clarified = 1
            WHERE id = ?~);
        $s->bind_param(1, $r->{answer}, { ora_type => 113 });
        $s->bind_param(2, $p->{qid});
        $s->execute;
        $dbh->commit;
        $t->param(clarified => 1);
    }
    else {
        $t->param(
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
    $t->param(%$r, verdict => $CATS::Verdicts::state_to_name->{$r->{state}});
}

sub questions_api {
    my ($p) = @_;
    $is_jury or return $p->print_json({});
    my $questions = $dbh->selectall_arrayref(q~
        SELECT
            CA.contest_id, A.team_name,
            Q.id, Q.submit_time, Q.clarification_time, Q.clarified, Q.question, Q.answer
        FROM questions Q
        INNER JOIN contest_accounts CA ON CA.id = Q.account_id
        INNER JOIN accounts A ON A.id = CA.account_id
        WHERE CA.contest_id = ? AND Q.clarified = ?~, { Slice => {} },
        $cid, $p->{clarified} ? 1 : 0);
    for my $q (@$questions) {
        $q->{$_} = Encode::decode_utf8($q->{$_}) for qw(answer question team_name);
    }
    $p->print_json({ questions => $questions });
}

1;
