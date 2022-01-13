package CATS::Awards;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($cid);
use CATS::Messages qw(msg);
use CATS::RankTable::Cache;

sub add_award {
    my ($accounts, $award_id) = @_;
    @$accounts && $award_id or return;
    $dbh->selectrow_array(q~
        SELECT 1 FROM awards WHERE contest_id = ? AND id = ?~, undef,
        $cid, $award_id) or return;
    my $has_award_sth = $dbh->prepare(q~
        SELECT A.team_name FROM contest_account_awards CAA
        INNER JOIN contest_accounts CA ON CA.id = CAA.ca_id
        INNER JOIN accounts A ON A.id = CA.account_id
        WHERE award_id = ? AND ca_id = ?~);
    my $add_sth = $dbh->prepare(q~
        INSERT INTO contest_account_awards (award_id, ca_id, ts)
        VALUES (?, ?, CURRENT_TIMESTAMP)~);
    my $added = 0;
    for (@$accounts) {
        $has_award_sth->execute($award_id, $_);
        my ($has_award) = $has_award_sth->fetchrow_array;
        $has_award_sth->finish;
        if ($has_award) {
            msg(1233, $has_award);
        }
        else {
            $added += $add_sth->execute($award_id, $_);
        }
    }
    $dbh->commit;
    CATS::RankTable::Cache::remove($cid) if $added;
    msg(1234, $added);
}

sub remove_award {
    my ($accounts, $award_id) = @_;
    @$accounts && $award_id or return;
    my $remove_sth = $dbh->prepare(q~
        DELETE FROM contest_account_awards WHERE award_id = ? AND ca_id = ?~);
    my $removed;
    for (@$accounts) {
        $removed += $remove_sth->execute($award_id, $_);
    }
    $dbh->commit;
    CATS::RankTable::Cache::remove($cid) if $removed;
    msg(1235, $removed);
}

1;
