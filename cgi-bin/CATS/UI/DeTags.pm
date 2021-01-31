package CATS::UI::DeTags;

use strict;
use warnings;

use CATS::Contest::Utils;
use CATS::DB;
use CATS::DeGrid;
use CATS::Form;
use CATS::Globals qw($cid $is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

my @field_common = (validators => [ CATS::Field::str_length(1, 200) ], editor => { size => 50 });

sub _get_all_des {
    $dbh->selectall_arrayref(q~
        SELECT D.id, D.code, D.description, D.in_contests,
            (SELECT 1 FROM de_de_tags DDT WHERE DDT.tag_id = ? AND DDT.de_id = D.id) AS include
        FROM default_de D
        ORDER BY D.code~, { Slice => {} }, $_[0]
    );
}

sub _set_des {
    my ($tag_id, $des) = @_;

    my $all_des = _get_all_des($tag_id);
    my (@delete_des, @insert_des);
    my ($delete_des, $insert_des) =
        CATS::DeGrid::calc_deletes_inserts($all_des, $des, 'id', 'include');

    @$delete_des || @$insert_des or return $all_des;

    if (@$delete_des) {
        $dbh->do(_u $sql->delete('de_de_tags',
            { tag_id => $tag_id, de_id => $delete_des }));
    }
    if (@$insert_des) {
        my $sth = $dbh->prepare(q~
            INSERT INTO de_de_tags(tag_id, de_id) VALUES (?, ?)~);
        $sth->execute($tag_id, $_) for @$insert_des;
    }
    $dbh->commit;

    msg(1169, scalar @$delete_des, scalar @$insert_des);
    $all_des;
}

our $form = CATS::Form->new(
    table => 'de_tags',
    fields => [
        [ name => 'name', @field_common, caption => 601 ],
    ],
    href_action => 'de_tags_edit',
    descr_field => 'name',
    template_var => 'dt',
    msg_saved => 1187,
    msg_deleted => 1188,
    before_display => sub {
        my ($fd, $p) = @_;
        $fd->{des} //= _get_all_des($fd->{id} // 0);
        $fd->{de_matrix} = CATS::DeGrid::matrix($fd->{des}, 3);
        $t->param(submenu => [ CATS::References::menu('de_tags') ]);
    },
    after_save => sub {
        my ($fd, $p) = @_;
        $fd->{des} = _set_des($fd->{id}, $p->{include});
    },
);

sub de_tags_edit_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'de_tags_edit.html.tt');
    $form->edit_frame($p, redirect_cancel => [ 'de_tags' ]);
}

sub de_tags_frame {
    my ($p) = @_;

    $is_jury or return;
    $form->delete_or_saved($p) if $is_root;
    init_template($p, 'de_tags');
    my $lv = CATS::ListView->new(web => $p, name => 'de_tags', url => url_f('de_tags'));

    CATS::Contest::Utils::add_remove_tags($p, 'contest_de_tags') if $p->{add} || $p->{remove};

    $lv->default_sort(0)->define_columns([
        { caption => res_str(601), order_by => 'name', width => '30%' },
        { caption => res_str(685), order_by => 'is_used', width => '10%' },
        { caption => res_str(643), order_by => 'ref_count', width => '10%', col => 'Rc' },
        { caption => res_str(641), order_by => 'de_count', width => '10%', col => 'Dc' },
    ]);
    $lv->define_db_searches([ qw(id name) ]);
    $lv->define_subqueries({
        in_contest => { sq => qq~EXISTS (
            SELECT 1 FROM contest_de_tags CDT1
            WHERE CDT1.contest_id = ? AND CDT1.tag_id = CT.id)~,
            m => 1192, t => q~
            SELECT C.title FROM contests C WHERE C.id = ?~
        },
    });
    $lv->define_enums({ in_contest => { this => $cid } });

    my $ref_count_sql = $lv->visible_cols->{Rc} ? q~
        SELECT COUNT(*) FROM contest_de_tags CDT2 WHERE CDT2.tag_id = DT.id~ : 'NULL';
    my $de_count_sql = $lv->visible_cols->{Dc} ? q~
        SELECT COUNT(*) FROM de_de_tags DDT2 WHERE DDT2.tag_id = DT.id~ : 'NULL';
    my $sth = $dbh->prepare(qq~
        SELECT DT.id, DT.name,
            (SELECT 1 FROM contest_de_tags CDT1
                WHERE CDT1.tag_id = DT.id AND CDT1.contest_id = ?) AS is_used,
            ($ref_count_sql) AS ref_count,
            ($de_count_sql) AS de_count
        FROM de_tags DT WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit=> url_f('de_tags_edit', id => $row->{id}),
            href_delete => url_f('de_tags', 'delete' => $row->{id}),
            href_view_contests => url_f('contests', search => "has_de_tag($row->{id})"),
        );
    };

    $lv->attach($fetch_record, $sth);

    $t->param(submenu => [ CATS::References::menu('de_tags') ], editable => $is_root);
}

1;
