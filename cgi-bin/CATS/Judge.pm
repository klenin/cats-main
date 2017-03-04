package CATS::Judge;

use strict;
use warnings;

use CATS::Config;
use CATS::Constants;
use CATS::DB;

sub ping {
    my ($jid) = @_;
    $dbh->do(qq~
        UPDATE judges SET is_alive = 0 WHERE is_alive = 1 AND id = ?~, undef,
        $jid);
    $dbh->commit;
}

sub get_active_count {
    $dbh->selectrow_array(qq~
        SELECT SUM(CASE WHEN CURRENT_TIMESTAMP - J.alive_date < ? THEN 1 ELSE 0 END), COUNT(*)
            FROM judges J WHERE J.pin_mode <> ?~, undef,
        3 * $CATS::Config::judge_alive_interval / 24, $cats::judge_pin_locked);
}

1;
