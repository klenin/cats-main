package CATS::AccGroups;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($cid);
use CATS::Messages qw(msg);

sub subquery {
    my ($lv, $join_field) = @_;
    $lv->define_subqueries({
        in_group => { sq => qq~EXISTS (
            SELECT 1 FROM acc_group_accounts AG WHERE AG.account_id = $join_field AND AG.acc_group_id = ?)~,
            m => 1226, t => q~SELECT name FROM acc_groups WHERE id = ?~
        },
    });
}

sub enum {
    my ($lv) = @_;
    my $acc_groups = $dbh->selectall_arrayref(q~
        SELECT AG.id, AG.name FROM acc_groups AG
        INNER JOIN acc_group_contests AGC ON AGC.acc_group_id = AG.id
        WHERE AGC.contest_id = ?~, { Slice => {} },
        $cid);
    if (@$acc_groups) {
        my %acc_groups_h;
        $acc_groups_h{$_->{name}} = $_->{id} for @$acc_groups;
        $lv->define_enums({ in_group => \%acc_groups_h });
    }
}

sub exclude_users {
    my ($group, $users) = @_;
    my $name_sth = $dbh->prepare(q~
        SELECT A.team_name
        FROM accounts A INNER JOIN acc_group_accounts AGA ON A.id = AGA.account_id
        WHERE AGA.acc_group_id = ? AND AGA.account_id = ?~);
    my $exclude_sth = $dbh->prepare(q~
        DELETE FROM acc_group_accounts
        WHERE acc_group_id = ? AND account_id = ?~);
    my @excluded;
    for my $user_id (@$users) {
        $name_sth->execute($group, $user_id);
        my $user_name = $name_sth->fetch;
        $name_sth->finish;
        push @excluded, $user_name if $user_name && $exclude_sth->execute($group, $user_id);
    }
    @excluded or return;
    $dbh->commit;
    msg(1227, scalar @excluded);
}

1;
