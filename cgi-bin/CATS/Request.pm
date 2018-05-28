package CATS::Request;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::IP;
use CATS::JudgeDB;
use CATS::Job;
use CATS::Messages qw(msg);

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

sub delete_logs {
    my ($request_id) = @_;
    my $jobs = $dbh->selectcol_arrayref(q~
        SELECT id FROM jobs WHERE req_id = ?~, undef,
        $request_id) or return;
    $dbh->do(_u $sql->delete('logs', { job_id => $jobs })) if @$jobs;
}

# Set request state manually. May be also used for retesting.
# Params: request_id, fields: { state (required), failed_test, testsets, points, judge_id, limits_id }
sub enforce_state {
    my ($request_id, $fields) = @_;
    $request_id && defined $fields->{state} or die;

    die if exists $fields->{elements_count} && !defined $fields->{elements_count};

    $dbh->do(_u $sql->update('reqs', {
        %$fields,
        received => 0,
        result_time => \'CURRENT_TIMESTAMP',
    }, { id => $request_id })) or return;

    CATS::JudgeDB::ensure_request_de_bitmap_cache($request_id);

    1;
}

# Params: problem_id (required), contest_id (required), submit_uid (required), de_bitmap (required),
#   fields: { state = $cats::st_not_processed, failed_test, testsets, points, judge_id, limits_id, elements_count, tag }
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

    CATS::Job::create($cats::job_type_submission, { req_id => $rid })
        if $fields->{state} == $cats::st_not_processed;

    $rid;
}

# source_p: src, de_id
sub update_source {
    my ($request_id, $source_p, $de_bitmap) = @_;
    $dbh->do(_u $sql->update(sources => $source_p, { req_id => $request_id }));

    $dbh->do(_u $sql->update('req_de_bitmap_cache', {
        req_id => $request_id,
        version => CATS::JudgeDB::current_de_version,
        CATS::JudgeDB::get_de_bitfields_hash(@$de_bitmap),
    })) if $de_bitmap;
}

# Params: request_ids (required), submit_uid (required)
#         fields: { state = $cats::st_not_processed, failed_test, testsets, points, judge_id, limits_id }
sub create_group {
    my ($request_ids, $submit_uid, $fields) = @_;

    $request_ids && $submit_uid or die;

    my $dev_env = CATS::DevEnv->new(CATS::JudgeDB::get_DEs);
    my $req_tree = CATS::JudgeDB::ensure_request_de_bitmap_cache($request_ids, $dev_env, 1);
    CATS::JudgeDB::add_info_to_req_tree({
        fields => [
            qw(R.problem_id R.contest_id)
        ]
    }, undef, $req_tree);

    my $problem_id = $req_tree->{$request_ids->[0]}->{problem_id};
    my $contest_id = $req_tree->{$request_ids->[0]}->{contest_id};

    return msg(1153) if grep $req_tree->{$_}->{contest_id} != $contest_id, keys %$req_tree;
    return msg(1154) if grep $req_tree->{$_}->{problem_id} != $problem_id, keys %$req_tree;

    my $players_count_str = $dbh->selectrow_array(q~
        SELECT P.players_count FROM problems P
        WHERE P.id = ?~, undef,
    $problem_id);

    my $players_count = CATS::Testset::parse_simple_rank($players_count_str) if $players_count_str;
    return if $players_count_str && !$players_count;

    return msg(1156, $players_count_str) if $players_count && !grep @$request_ids == $_, @$players_count;

    my @element_request_ids;
    my $seened = {};
    my $collect_requests;
    $collect_requests = sub {
        my ($req) = @_;

        return if $seened->{$req->{id}};
        $seened->{$req->{id}} = 1;

        if ($req->{elements_count} == 0 ||
            $req->{elements_count} == 1 && $req->{elements}->[0]->{elements_count} == 0
        ) {
            push @element_request_ids, $req->{id};
        } else {
            $collect_requests->($_) for @{$req->{elements}};
        }
    };
    $collect_requests->($req_tree->{$_}) for @$request_ids;

    my @req_de_bitmap = (0) x $cats::de_req_bitfields_count;
    for my $req_id (@element_request_ids) {
        $req_de_bitmap[$_] |= $req_tree->{$req_id}->{bitmap}->[$_]
            for 0 .. $cats::de_req_bitfields_count - 1;
    }

    $fields->{elements_count} = @element_request_ids;

    my $group_req_id = insert($problem_id, $contest_id, $submit_uid, \@req_de_bitmap, $fields) or die;

    my $c = $dbh->prepare(q~
        INSERT INTO req_groups (element_id, group_id) VALUES (?, ?)~);
    $c->execute_array(undef, \@element_request_ids, $group_req_id);

    $group_req_id;
}

# Params: request_ids (required), contest_id, submit_uid (required)
#         fields: { state = $cats::st_not_processed, failed_test, testsets, points, judge_id, limits_id }
sub clone {
    my ($request_ids, $contest_id, $submit_uid, $fields) = @_;

    $request_ids && $submit_uid or die;

    my @request_ids = ref($request_ids) ? @$request_ids : ($request_ids);

    my $dev_env = CATS::DevEnv->new(CATS::JudgeDB::get_DEs);
    my $req_tree = CATS::JudgeDB::ensure_request_de_bitmap_cache(\@request_ids, $dev_env, 1);
    CATS::JudgeDB::add_info_to_req_tree({
        fields => [
            qw(R.problem_id R.contest_id)
        ]
    }, undef, $req_tree);

    my @element_requests;
    my $collect_requests; # Recursive.
    $collect_requests = sub {
        my ($req) = @_;

        if ($req->{elements_count} == 0) {
            push @element_requests, $req;
        } else {
            $collect_requests->($_) for @{$req->{elements}};
        }
    };
    $collect_requests->($req_tree->{$_}) for @request_ids;

    my @req_groups = map [
        $_->{id},
        insert(
            $_->{problem_id}, $_->{contest_id}, $submit_uid, $_->{bitmap},
            { $fields ? %$fields : (), elements_count => 1 })
    ], @element_requests;

    my $c = $dbh->prepare(q~
        INSERT INTO req_groups (element_id, group_id) VALUES (?, ?)~);
    $c->execute_array(undef, [ map $_->[0], @req_groups ], [ map $_->[1], @req_groups ]);

    @req_groups == 1 && !ref($request_ids) ? $req_groups[0]->[1] : [ map $_->[1], @req_groups ];
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
