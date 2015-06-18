package CATS::UI::Messages;

use strict;
use warnings;

use CATS::Web qw(param url_param);
use CATS::DB;
use CATS::Misc qw($t $is_jury $is_team $uid init_template res_str);
use CATS::Utils qw(state_to_display);


sub send_message_box_frame
{
    init_template('send_message_box.html.tt');
    $is_jury or return;

    my $caid = url_param('caid') or return;

    my $team_name = $dbh->selectrow_array(q~
        SELECT A.team_name
        FROM accounts A INNER JOIN contest_accounts CA ON CA.account_id = A.id WHERE CA.id = ?~, undef,
        $caid) or return;

    $t->param(team => $team_name, title_suffix => res_str(567));

    defined param('send') or return;
    my $message_text = param('message_text') or return;

    my $s = $dbh->prepare(qq~
        INSERT INTO messages (id, send_time, text, account_id, received)
            VALUES (?, CURRENT_TIMESTAMP, ?, ?, 0)~);
    $s->bind_param(1, new_id);
    $s->bind_param(2, $message_text, { ora_type => 113 });
    $s->bind_param(3, $caid);
    $s->execute;
    $dbh->commit;
    $t->param(sent => 1);
}


sub answer_box_frame
{
    init_template('answer_box.html.tt');
    $is_jury or return;

    my $qid = url_param('qid');

    my $r = $dbh->selectrow_hashref(qq~
        SELECT
            Q.account_id AS caid, CA.account_id AS aid, A.login, A.team_name,
            Q.submit_time, Q.question, Q.clarified, Q.answer
        FROM questions Q
            INNER JOIN contest_accounts CA ON CA.id = Q.account_id
            INNER JOIN accounts A ON A.id = CA.account_id
        WHERE Q.id = ?~, { Slice => {} },
        $qid);
    $_ = Encode::decode_utf8($_) for @$r{qw(question answer)};

    $t->param(team_name => $r->{team_name}, title_suffix => res_str(566));

    if (defined param('clarify') && (my $a = Encode::decode_utf8(param('answer_text'))))
    {
        $r->{answer} ||= '';
        $r->{answer} .= " $a";

        my $s = $dbh->prepare(qq~
            UPDATE questions
                SET clarification_time = CURRENT_TIMESTAMP, answer = ?, received = 0, clarified = 1
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


sub envelope_frame
{
    init_template('envelope.html.tt');

    $is_team && (my $rid = url_param('rid')) or return;

    my $r = $dbh->selectrow_hashref(qq~
        SELECT R.submit_time, R.test_time, R.state, R.failed_test, R.account_id, A.team_name, C.title, 
            RD.ac AS accepted_count, RD.tc AS total_count
            FROM reqs R
            INNER JOIN contests C ON C.id = R.contest_id
            INNER JOIN  accounts A ON A.id = R.account_id
            LEFT OUTER JOIN (SELECT 
                req_id,
                count(req_id) AS tc,
                sum(case result when $cats::st_accepted then 1 else null end) AS ac
                FROM req_details
                GROUP BY req_id
            ) RD ON RD.req_id=R.id
            WHERE R.id = ? AND R.account_id = ?~, { Slice => {} },
        $rid, $uid) or return;
    $t->param(%$r, state_to_display($r->{state}));
}


1;
