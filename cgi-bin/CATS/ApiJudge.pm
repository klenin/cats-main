package CATS::ApiJudge;

use strict;
use warnings;

use JSON::XS;

use CATS::DB;
use CATS::Misc qw($sid);
use CATS::Web;

sub print_json {
    CATS::Web::content_type('application/json');
    CATS::Web::print(encode_json($_[0]));
    -1;
}

sub get_judge_id {
    my $id = $sid && $dbh->selectrow_array(q~
        SELECT J.id FROM judges J LEFT JOIN accounts A
        ON A.id = J.account_id WHERE A.sid = ?~, undef,
        $sid);
    print_json($id ? { id => $id } : { error => 'bad sid' });
}

sub update_state {
    $sid or print_json({ error => "bad sid"});

    my ($is_alive, $lock_counter, $jid, $time_since_alive) = $dbh->selectrow_array(q~
        SELECT J.is_alive, J.lock_counter, J.id, CURRENT_TIMESTAMP - J.alive_date
        FROM judges J INNER JOIN accounts A ON J.account_id = A.id WHERE A.sid = ?~, undef,
        $sid);

    $dbh->do(q~
        UPDATE judges SET is_alive = 1, alive_date = CURRENT_TIMESTAMP WHERE id = ?~, undef,
        $jid) if !$is_alive || $time_since_alive > $CATS::Config::judge_alive_interval / 24;
    $dbh->commit;

    print_json({ lock_counter => $lock_counter, is_alive => $is_alive });
}

1;
