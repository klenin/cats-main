package CATS::Request;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::IP;
use CATS::JudgeDB;
use CATS::Misc qw(msg);

# Params: limits: { time_limit, memory_limit }
sub filter_valid_limits {
    my ($limits) = @_;

    my %validators = (
        time_limit => sub { $_[0] =~ m/^\+?([0-9]*[.])?[0-9]+$/ },
        memory_limit => sub { $_[0] =~ m/^\+?\d+$/ },
        write_limit => sub { $_[0] =~ m/^\+?\d+$/ },
        save_output_prefix => sub { $_[0] =~ m/^\+?\d+$/ },
    );

    return { map { $_ => $limits->{$_} } grep $validators{$_}->($limits->{$_} // ''), @cats::limits_fields };
}

# Params: limits_id = new_id, limits: { time_limit, memory_limit }
sub set_limits {
    my ($limits_id, $limits) = @_;

    %$limits or return;

    $dbh->do(_u $limits_id ?
        $sql->update('limits', { map { $_ => $limits->{$_} } @cats::limits_fields }, { id => $limits_id }) :
        $sql->insert('limits', { id => ($limits_id = new_id), %$limits }));

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

    $dbh->do(_u $sql->update('reqs', {
        %$fields,
        received => 0,
        result_time => \'CURRENT_TIMESTAMP',
    }, { id => $request_id })) or return;

    CATS::JudgeDB::ensure_request_de_bitmap_cache($request_id);

    # Save log for ignored requests.
    if ($fields->{state} != $cats::st_ignore_submit) {
        $dbh->do(q~
            DELETE FROM log_dumps WHERE req_id = ?~, undef,
            $fields->{request_id}
        ) or return;
    }

    return 1;
}

# Params: problem_id (required), contest_id (required), submit_uid (required), de_bitmap (required),
#         fields: { state = $cats::st_not_processed, failed_test, testsets, points, judge_id, limits_id, elements_count }
sub insert {
    my ($problem_id, $contest_id, $submit_uid, $de_bitmap, $fields) = @_;

    $problem_id && $submit_uid && $contest_id && $de_bitmap && @$de_bitmap or die;

    die 'too many de codes to fit it in db' if @$de_bitmap > $cats::de_req_bitfields_count;

    $fields ||= {};
    $fields->{state} ||= $cats::st_not_processed;

    my $rid = new_id;
    $dbh->do(_u $sql->insert('reqs', {
        %$fields,
        id => $rid,
        problem_id => $problem_id,
        contest_id => $contest_id,
        account_id => $submit_uid,
        submit_time => \'CURRENT_TIMESTAMP',
        test_time => \'CURRENT_TIMESTAMP',
        result_time => \'CURRENT_TIMESTAMP',
        received => 0,
    })) or return;

    $dbh->do(_u $sql->insert('req_de_bitmap_cache', {
        req_id => $rid,
        version => CATS::JudgeDB::current_de_version,
        CATS::JudgeDB::get_de_bitfields_hash(@$de_bitmap),
    })) or return;

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

    my $dev_env = CATS::DevEnv->new(CATS::JudgeDB::get_DEs);

    my $de_bitfields_list = CATS::JudgeDB::de_bitmap_str('RDEBC');
    my $reqs = $dbh->selectall_arrayref(qq~
        SELECT R.id, R.problem_id, R.contest_id, $de_bitfields_list, RDEBC.version as de_version
        FROM reqs R
            LEFT JOIN req_de_bitmap_cache RDEBC ON RDEBC.req_id = R.id
        WHERE R.id IN ($req_id_list)~, { Slice => {} }) or return;

    my $problem_id = $reqs->[0]->{problem_id};
    my $contest_id = $reqs->[0]->{contest_id};

    return msg(1153) if grep $_->{contest_id} != $contest_id, @$reqs;
    return msg(1154) if grep $_->{problem_id} != $problem_id, @$reqs;

    my $players_count_str = $dbh->selectrow_array(q~
        SELECT P.players_count FROM problems P
        WHERE P.id = ?~, undef,
    $problem_id);

    my $players_count = CATS::Testset::parse_simple_rank($players_count_str) if $players_count_str;
    return if $players_count_str && !$players_count;

    return msg(1156, $players_count_str) if $players_count && !grep @$request_ids == $_, @$players_count;

    my @update_req_ids = map $_->{id}, grep !$dev_env->is_good_version($_->{de_version}), @$reqs;
    my $updated_reqs = CATS::JudgeDB::ensure_request_de_bitmap_cache(\@update_req_ids, $dev_env);
    my %req_des =
        (( map { $_->{id} => [ CATS::JudgeDB::extract_de_bitmap($_) ] } grep { $dev_env->is_good_version($_->{de_version}) } @$reqs ),
        ( map { $_->{id} => $_->{bitmap} } values %$updated_reqs ));

    my $req_de_bitmap = [ map 0, 1..$cats::de_req_bitfields_count ];
    for my $req (@$reqs) {
        $req_de_bitmap->[$_] |= $req_des{$req->{id}}->[$_] for 0..($cats::de_req_bitfields_count-1);
    }

    $fields->{elements_count} = @$request_ids;

    my $group_req_id = insert($problem_id, $contest_id, $submit_uid, $req_de_bitmap, $fields) or die;

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

    my $de_bitfields_list = CATS::JudgeDB::de_bitmap_str('RDEBC');
    my $req = $dbh->selectrow_hashref(qq~
        SELECT R.problem_id, R.contest_id, $de_bitfields_list, RDEBC.version AS de_version
        FROM reqs R
            LEFT JOIN req_de_bitmap_cache RDEBC ON RDEBC.req_id = R.id
        WHERE R.id = ?~, undef,
        $element_req_id);

    my $de_bitmap = defined $req->{de_version} && $req->{de_version} == CATS::JudgeDB::current_de_version() ?
        [ CATS::JudgeDB::extract_de_bitmap($req) ] :
        CATS::JudgeDB::ensure_request_de_bitmap_cache($request_id)->{$request_id}->{bitmap};

    $fields->{elements_count} = 1;

    my $group_req_id = insert($req->{problem_id}, $contest_id, $submit_uid, $de_bitmap, $fields) or die;

    $dbh->do(q~
        INSERT INTO req_groups (element_id, group_id) VALUES (?, ?)~, undef,
        $element_req_id, $group_req_id);

    $group_req_id;
}

sub delete {
    my ($req_id) = @_;

    my $group_req_ids = $dbh->selectcol_arrayref(q~
        SELECT RG.group_id FROM req_groups RG
        WHERE RG.element_id = ?~, { Slice => {} },
        $req_id);

    my $group_req_id_list = join ', ', @$group_req_ids;
    $dbh->do(qq~
        UPDATE reqs R SET R.elements_count = R.elements_count - 1
        WHERE R.id IN ($group_req_id_list)~) if @$group_req_ids;

    $dbh->do(q~
        DELETE FROM reqs WHERE id = ?~, undef,
        $req_id);
}

1;
