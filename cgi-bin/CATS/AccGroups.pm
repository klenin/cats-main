package CATS::AccGroups;

use CATS::DB;
use CATS::Globals qw($cid);

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

1;
