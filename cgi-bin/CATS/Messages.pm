package CATS::Messages;

use strict;
use warnings;

use CATS::Web qw(param url_param);
use CATS::DB;
use CATS::Misc qw($t $is_jury init_template);

sub send_message_box_frame
{
    init_template('send_message_box.html.tt');
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
                VALUES (?, CURRENT_TIMESTAMP, ?, ?, 0)~);
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

    $t->param(team_name => $r->{team_name});

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


1;
