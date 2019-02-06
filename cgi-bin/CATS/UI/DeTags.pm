package CATS::UI::DeTags;

use strict;
use warnings;

use CATS::DB;
use CATS::Form;
use CATS::Globals qw($cid $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

my @field_common = (validators => [ CATS::Field::str_length(1, 200) ], editor => { size => 50 });

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
    before_display => sub { $t->param(submenu => [ CATS::References::menu('de_tags') ]) },
);

sub de_tags_edit_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'de_tags_edit.html.tt');
    $form->edit_frame($p, redirect => [ 'de_tags' ]);
}

sub _add_remove {
    my ($p) = @_;
    my $existing = $dbh->selectcol_arrayref(q~
        SELECT tag_id FROM contest_de_tags WHERE contest_id = ?~, undef,
        $cid);
    my %existing_idx;
    @existing_idx{@$existing} = undef;
    my $count = 0;
    if ($p->{add}) {
        my $q = $dbh->prepare(q~
            INSERT INTO contest_de_tags (contest_id, tag_id) VALUES (?, ?)~);
        for (@{$p->{check}}) {
            exists $existing_idx{$_} and next;
            $q->execute($cid, $_);
            ++$count;
        }
        $dbh->commit;
        msg(1189, $count);
    }
    elsif ($p->{remove}) {
        my $q = $dbh->prepare(q~
            DELETE FROM contest_de_tags WHERE contest_id = ? AND tag_id = ?~);
        for (@{$p->{check}}) {
            exists $existing_idx{$_} or next;
            $q->execute($cid, $_);
            ++$count;
        }
        $dbh->commit;
        msg(1190, $count);
    }
}

sub de_tags_frame {
    my ($p) = @_;

    $is_root or return;
    $form->delete_or_saved($p) if $is_root;
    init_template($p, 'de_tags.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'de_tags');

    _add_remove($p) if $p->{add} || $p->{remove};

    $lv->define_columns(url_f('de_tags'), 0, 0, [
        { caption => res_str(601), order_by => 'name', width => '30%' },
        { caption => res_str(685), order_by => 'is_used', width => '10%' },
        { caption => res_str(643), order_by => 'ref_count', width => '10%', col => 'Rc' },
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
    my $c = $dbh->prepare(qq~
        SELECT DT.id, DT.name,
            (SELECT 1 FROM contest_de_tags CDT1
                WHERE CDT1.tag_id = DT.id AND CDT1.contest_id = ?) AS is_used,
            ($ref_count_sql) AS ref_count
        FROM de_tags DT WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $c->execute($cid, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit=> url_f('de_tags_edit', id => $row->{id}),
            href_delete => url_f('de_tags', 'delete' => $row->{id}),
            href_view_contests => url_f('contests', search => "has_de_tag($row->{id})"),
        );
    };

    $lv->attach(url_f('de_tags'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('de_tags') ], editable => $is_root);
}

1;
