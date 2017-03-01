package CATS::Request;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::IP;

# Set request state manually. May be also used for retesting.
# Params: request_id, fields: { state (required), failed_test, testsets, points, judge_id }
sub enforce_state {
    my ($request_id, $fields) = @_;
    $request_id && defined $fields->{state} or die;

    my ($stmt, @bind) = $sql->update('reqs', { %$fields, received => 0, result_time => \'CURRENT_TIMESTAMP' }, { id => $request_id });
    $dbh->do($stmt, undef, @bind) or return;
    # Save log for ignored requests.
    if ($fields->{state} != $cats::st_ignore_submit) {
        $dbh->do(q~
            DELETE FROM log_dumps WHERE req_id = ?~, undef,
            $fields->{request_id}
        ) or return;
    }

    return 1;
}

# Params: problem_id (required), contest_id (required), submit_uid (required)
#         fields: { state = $cats::st_not_processed, failed_test, testsets, points, judge_id }
sub insert {
    my ($problem_id, $contest_id, $submit_uid, $fields) = @_;

    $problem_id && $submit_uid && $contest_id or die;

    $fields ||= {};
    $fields->{state} ||= $cats::st_not_processed;

    my $rid = new_id;
    my ($stmt, @bind) = $sql->insert('reqs', {
        %$fields,
        id => $rid,
        problem_id => $problem_id,
        contest_id => $contest_id,
        account_id => $submit_uid,
        submit_time => \'CURRENT_TIMESTAMP',
        test_time => \'CURRENT_TIMESTAMP',
        result_time => \'CURRENT_TIMESTAMP',
        received => 0,
    });

    $dbh->do($stmt, undef, @bind) or return;

    $dbh->do(q~
        INSERT INTO events (id, event_type, ts, account_id, ip)
        VALUES (?, ?, CURRENT_TIMESTAMP, ?, ?)~,
        undef,
        $rid, 1, $submit_uid, CATS::IP::get_ip);
    $rid;
}

# Params: request_id (required), contest_id (required), submit_uid (required)
#         fields: { state = $cats::st_not_processed, failed_test, testsets, points, judge_id }
sub clone {
    my ($request_id, $contest_id, $submit_uid, $fields) = @_;

    $request_id && $submit_uid && $contest_id or die;

    my $element_req_id = $dbh->selectrow_array(q~
        SELECT RG.element_id FROM req_groups RG
        WHERE RG.group_id = ?~, undef,
        $request_id) || $request_id;

    my $req = $dbh->selectrow_hashref(q~
        SELECT R.problem_id, R.contest_id FROM reqs R
        WHERE R.id = ?~, undef,
        $element_req_id);

    my $group_req_id = insert($req->{problem_id}, $contest_id, $submit_uid, $fields) or die;

    $dbh->do(q~
        INSERT INTO req_groups (element_id, group_id) VALUES (?, ?)~, undef,
        $element_req_id, $group_req_id);

    $group_req_id;
}

1;
