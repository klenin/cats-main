package CATS::AccGroups;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($cid);
use CATS::Messages qw(msg);

sub subquery {
    my ($lv, $join_field) = @_;
    my $sq = sub {
        my ($alias, $cond) = @_;
        { sq => qq~EXISTS (
            SELECT 1 FROM acc_group_accounts $alias
            WHERE $alias.account_id = $join_field AND $alias.acc_group_id = ?$cond)~,
            m => 1226, t => q~SELECT name FROM acc_groups WHERE id = ?~
        };
    };
    $lv->define_subqueries({
        in_group => $sq->('AGA1', q~ AND AGA1.is_hidden = 0~),
        in_group_hidden => $sq->('AGA2', ''),
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
        $lv->define_enums({ in_group => \%acc_groups_h, in_group_hidden => \%acc_groups_h });
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

sub add_accounts {
    my ($accounts, $group_id, $make_hidden, $make_admin) = @_;
    my $in_group_sth = $dbh->prepare(q~
        SELECT 1 FROM acc_group_accounts WHERE acc_group_id = ? AND account_id = ?~);
    my $add_sth = $dbh->prepare(q~
        INSERT INTO acc_group_accounts (acc_group_id, account_id, is_hidden, is_admin, date_start)
        VALUES (?, ?, ?, ?, CURRENT_DATE)~);
    my @new_accounts;
    for (@$accounts) {
        $in_group_sth->execute($group_id, $_);
        my ($in_group) = $in_group_sth->fetchrow_array;
        $in_group_sth->finish;
        $in_group ? msg(1120, $_) : push @new_accounts, $_;
    }
    for (@new_accounts) {
        $add_sth->execute($group_id, $_, $make_hidden ? 1 : 0, $make_admin ? 1 : 0);
    }
    $dbh->commit;
    \@new_accounts;
}

1;
