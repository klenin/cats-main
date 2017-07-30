package CATS::ContestParticipate;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::Misc qw($is_root $is_jury $is_team $is_virtual $cid $uid $contest $user msg);

use Exporter qw(import);

our @EXPORT = qw(
    get_registered_contestant
    is_jury_in_contest
);

# Params: fields, contest_id, account_id.
sub get_registered_contestant {
    my %p = @_;
    $p{fields} ||= 1;
    $p{account_id} ||= $uid or return;
    $p{contest_id} or die;

    $dbh->selectrow_array(qq~
        SELECT $p{fields} FROM contest_accounts WHERE contest_id = ? AND account_id = ?~, undef,
        $p{contest_id}, $p{account_id});
}

sub is_jury_in_contest {
    my %p = @_;
    return 1 if $is_root;
    # Optimization: if the request is about the current contest, return cached value.
    return $is_jury if defined $cid && $p{contest_id} == $cid;
    my ($j) = get_registered_contestant(fields => 'is_jury', @_);
    return $j;
}

sub online {
    !get_registered_contestant(contest_id => $cid)
        or return msg(1111, $contest->{title});

    if ($is_root) {
        $contest->register_account(account_id => $uid, is_jury => 1, is_pop => 1, is_hidden => 1);
    }
    else {
        !$contest->{closed} or return msg(1105, $contest->{title});
        $contest->{time_since_finish} <= 0 or return msg(1108, $contest->{title});
        $contest->register_account(account_id => $uid);
    }
    $dbh->commit;
    $is_team = 1;
    msg(1110, $contest->{title});
}

sub virtual {
    my ($registered, $is_already_virtual, $is_remote) = get_registered_contestant(
         fields => '1, is_virtual, is_remote', contest_id => $cid);

    !$registered || $is_already_virtual
        or return msg(1114, $contest->{title});

    !$contest->{closed}
        or return msg(1105, $contest->{title});

    $contest->{time_since_start} >= 0
        or return msg(1109);

    # In official contests, virtual participation is allowed only after the finish.
    $contest->{time_since_finish} >= 0 || !$contest->{is_official}
        or return msg(1122);

    my $removed_req_count = 0;
    # Repeat virtual registration removes old results.
    if ($registered) {
        $removed_req_count = $dbh->do(q~
            DELETE FROM reqs WHERE account_id = ? AND contest_id = ?~, undef,
            $uid, $cid);
        $dbh->do(q~
            DELETE FROM contest_accounts WHERE account_id = ? AND contest_id = ?~, undef,
            $uid, $cid);
    }

    $contest->register_account(
        contest_id => $cid, account_id => $uid,
        is_virtual => 1, is_remote => $is_remote,
        diff_time => $contest->{time_since_start});
    $dbh->commit;
    $is_team = 1;
    $is_virtual = 1;
    $user->{diff_time} = $contest->{time_since_start};
    msg($removed_req_count > 0 ? 1113 : 1112, $contest->{title}, $removed_req_count);
}

1;
