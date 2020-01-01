package CATS::UI::AccGroups;

use strict;
use warnings;

use CATS::DB;
use CATS::Form;
use CATS::Globals qw($cid $is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

our $form = CATS::Form->new(
    table => 'acc_groups',
    fields => [
        [ name => 'name', validators => [ CATS::Field::str_length(1, 200) ], editor => { size => 50 }, caption => 601 ],
        [ name => 'description', caption => 620 ],
    ],
    href_action => 'acc_groups_edit',
    descr_field => 'name',
    template_var => 'ag',
    msg_saved => 1215,
    msg_deleted => 1216,
    before_display => sub { $t->param(submenu => [ CATS::References::menu('acc_groups') ]) },
);

sub acc_groups_edit_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'acc_groups_edit.html.tt');
    $form->edit_frame($p, redirect => [ 'acc_groups' ]);
}

sub acc_groups_frame {
    my ($p) = @_;

    $is_jury or return;
    $form->delete_or_saved($p) if $is_root;
    init_template($p, 'acc_groups.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'acc_groups');

    #CATS::Contest::Utils::add_remove_tags($p, 'contest_contest_tags') if $p->{add} || $p->{remove};

    $lv->define_columns(url_f('acc_groups'), 0, 0, [
        { caption => res_str(601), order_by => 'name', width => '30%' },
        { caption => res_str(685), order_by => 'is_used', width => '10%' },
        { caption => res_str(643), order_by => 'ref_count', width => '10%', col => 'Rc' },
    ]);
    $lv->define_db_searches([ qw(id name description) ]);
    $lv->define_subqueries({
        in_contest => { sq => qq~EXISTS (
            SELECT 1 FROM acc_group_contests AGC
            WHERE AGC.contest_id = ? AND AGC.acc_group_id = AG.id)~,
            m => 1217, t => q~
            SELECT C.title FROM contests C WHERE C.id = ?~
        },
    });
    $lv->define_enums({ in_contest => { this => $cid } });

    my $ref_count_sql = $lv->visible_cols->{Rc} ? q~
        SELECT COUNT(*) FROM acc_group_contests AGC2 WHERE AGC2.acc_group_id = AG.id~ : 'NULL';
    my $c = $dbh->prepare(qq~
        SELECT AG.id, AG.name,
            (SELECT 1 FROM acc_group_contests AGC1
                WHERE AGC1.acc_group_id = AG.id AND AGC1.contest_id = ?) AS is_used,
            ($ref_count_sql) AS ref_count
        FROM acc_groups AG WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $c->execute($cid, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit=> url_f('acc_groups_edit', id => $row->{id}),
            href_delete => url_f('acc_groups', 'delete' => $row->{id}),
            href_view_contests => url_f('acc_groups', search => "has_group($row->{id})"),
        );
    };

    $lv->attach(url_f('acc_groups'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('acc_groups') ], editable => $is_root);
}

1;
