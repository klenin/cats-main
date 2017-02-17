package CATS::Request;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::IP;
use CATS::Misc qw($cid);

# Set request state manually. May be also used for retesting.
# Params: request_id, state, failed_test, testsets, points, judge_id.
sub enforce_state {
    my %p = @_;
    defined $p{state} && $p{request_id} or die;
    $dbh->do(q~
        UPDATE reqs
            SET failed_test = ?, state = ?, testsets = ?,
                points = ?, received = 0, result_time = CURRENT_TIMESTAMP, judge_id = ?
            WHERE id = ?~, undef,
        $p{failed_test}, $p{state}, $p{testsets}, $p{points}, $p{judge_id}, $p{request_id}
    ) or return;
    # Save log for ignored requests.
    if ($p{state} != $cats::st_ignore_submit) {
        $dbh->do(q~
            DELETE FROM log_dumps WHERE req_id = ?~, undef,
            $p{request_id}
        ) or return;
    }
    $dbh->commit;
    return 1;
}

sub insert {
    my ($pid, $submit_uid, $state, $contest_id) = @_;

    $contest_id ||= $cid;

    my $rid = new_id;
    $dbh->do(q~
        INSERT INTO reqs (
            id, account_id, problem_id, contest_id,
            submit_time, test_time, result_time, state, received
        ) VALUES (
            ?, ?, ?, ?,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?, ?)~,
        undef,
        $rid, $submit_uid, $pid, $contest_id, $state, 0);
    $dbh->do(q~
        INSERT INTO events (id, event_type, ts, account_id, ip)
        VALUES (?, ?, CURRENT_TIMESTAMP, ?, ?)~,
        undef,
        $rid, 1, $submit_uid, CATS::IP::get_ip);
    $rid;
}

sub clone {
    my ($element_req_id, $submit_uid) = @_;

    $element_req_id = $dbh->selectrow_array(q~
        SELECT RG.element_id FROM req_groups RG
        WHERE RG.group_id = ?~, undef,
        $element_req_id) || $element_req_id;

    my $req = $dbh->selectrow_hashref(q~
        SELECT R.problem_id, R.contest_id FROM reqs R
        WHERE R.id = ?~, undef,
        $element_req_id);

    my $group_req_id = insert(
        $req->{problem_id}, $submit_uid, $cats::st_not_processed, $req->{contest_id});

    $dbh->do(q~
        INSERT INTO req_groups (element_id, group_id) VALUES (?, ?)~, undef,
        $element_req_id, $group_req_id);

    $dbh->commit;

    $group_req_id;
}

1;
