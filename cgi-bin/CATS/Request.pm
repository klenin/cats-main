package CATS::Request;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::IP;
use CATS::Misc qw(msg);

# Params: limits: { time_limit, memory_limit }
sub filter_valid_limits {
    my ($limits) = @_;

    my %validators = (
        time_limit => sub { return 1; $_[0] =~ m/^\+?([0-9]*[.])?[0-9]+$/ },
        memory_limit => sub { return 1; $_[0] =~ m/^\+?\d+$/ },
    );

    return { map { $_ => $limits->{$_} } grep $validators{$_}->($limits->{$_} // ''), @cats::limits_fields };
}

# Params: limits_id = new_id, limits: { time_limit, memory_limit }
sub set_limits {
    my ($limits_id, $limits) = @_;

    %$limits or return;

    my ($stmt, @bind) = $limits_id ?
        $sql->update('limits', { map { $_ => $limits->{$_} } @cats::limits_fields }, { id => $limits_id }) :
        $sql->insert('limits', { id => ($limits_id = new_id), %$limits });

    $dbh->do($stmt, undef, @bind);

    $limits_id;
}

sub clone_limits {
    my ($limits_id) = @_;

    $limits_id or die;

    my $cloned_limits_id = new_id;
    my $limits_keys_list = join ', ', @cats::limits_fields;

    $dbh->do(qq~
        INSERT INTO LIMITS (id, $limits_keys_list)
        SELECT ?, $limits_keys_list FROM LIMITS WHERE id = ?~, undef,
        $cloned_limits_id, $limits_id
    );

    $cloned_limits_id
}

sub delete_limits {
    my ($limits_id) = @_;

    $limits_id or die;

    $dbh->do(q~
        DELETE FROM limits WHERE id = ?~, undef,
        $limits_id);
}

# Set request state manually. May be also used for retesting.
# Params: request_id, fields: { state (required), failed_test, testsets, points, judge_id, limits_id }
sub enforce_state {
    my ($request_id, $fields) = @_;
    $request_id && defined $fields->{state} or die;

    my ($stmt, @bind) = $sql->update('reqs',
        { %$fields, received => 0, result_time => \'CURRENT_TIMESTAMP' }, { id => $request_id });
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
#         fields: { state = $cats::st_not_processed, failed_test, testsets, points, judge_id, limits_id }
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

# Params: request_ids (required), submit_uid (required)
#         fields: { state = $cats::st_not_processed, failed_test, testsets, points, judge_id, limits_id }
sub create_group {
    my ($request_ids, $submit_uid, $fields) = @_;

    $request_ids && $submit_uid or die;

    my $req_id_list = join ', ', @$request_ids;

    my $elements_reqs = $dbh->selectcol_arrayref(qq~
        SELECT DISTINCT RG.group_id FROM req_groups RG
        WHERE RG.group_id IN ($req_id_list)~);
    return msg(1152, join ', ', @$elements_reqs) if @$elements_reqs;

    my $reqs = $dbh->selectall_arrayref(qq~
        SELECT R.id, R.problem_id, R.contest_id FROM reqs R
        WHERE R.id IN ($req_id_list)~, { Slice => {} }) or return;

    my $problem_id = $reqs->[0]->{problem_id};
    my $contest_id = $reqs->[0]->{contest_id};

    return msg(1153) if grep $_->{contest_id} != $contest_id, @$reqs;
    return msg(1154) if grep $_->{problem_id} != $problem_id, @$reqs;

    my $group_req_id = insert($problem_id, $contest_id, $submit_uid, $fields) or die;

    my $c = $dbh->prepare(q~
        INSERT INTO req_groups (element_id, group_id) VALUES (?, ?)~);
    $c->execute_array(undef, $request_ids, $group_req_id);

    $group_req_id;
}

# Params: request_id (required), contest_id (required), submit_uid (required)
#         fields: { state = $cats::st_not_processed, failed_test, testsets, points, judge_id, limits_id }
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
