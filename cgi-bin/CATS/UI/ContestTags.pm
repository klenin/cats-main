package CATS::UI::ContestTags;

use strict;
use warnings;

use CATS::Contest::Utils;
use CATS::DB;
use CATS::Form;
use CATS::Globals qw($cid $is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

my @field_common = (validators => [ CATS::Field::str_length(1, 200) ], editor => { size => 50 });

our $form = CATS::Form->new(
    table => 'contest_tags',
    fields => [
        [ name => 'name', @field_common, caption => 601 ],
    ],
    href_action => 'contest_tags_edit',
    descr_field => 'name',
    template_var => 'ct',
    msg_saved => 1187,
    msg_deleted => 1188,
    before_display => sub { $t->param(submenu => [ CATS::References::menu('contest_tags') ]) },
);

sub contest_tags_edit_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'contest_tags_edit.html.tt');
    $form->edit_frame($p, redirect => [ 'contest_tags' ]);
}

sub contest_tags_frame {
    my ($p) = @_;

    $is_jury or return;
    $form->delete_or_saved($p) if $is_root;
    init_template($p, 'contest_tags.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'contest_tags');

    CATS::Contest::Utils::add_remove_tags($p, 'contest_contest_tags') if $p->{add} || $p->{remove};

    $lv->define_columns(url_f('contest_tags'), 0, 0, [
        { caption => res_str(601), order_by => 'name', width => '30%' },
        { caption => res_str(685), order_by => 'is_used', width => '10%' },
        { caption => res_str(643), order_by => 'ref_count', width => '10%', col => 'Rc' },
    ]);
    $lv->define_db_searches([ qw(id name) ]);
    $lv->define_subqueries({
        in_contest => { sq => qq~EXISTS (
            SELECT 1 FROM contest_contest_tags CCT1
            WHERE CCT1.contest_id = ? AND CCT1.tag_id = CT.id)~,
            m => 1192, t => q~
            SELECT C.title FROM contests C WHERE C.id = ?~
        },
    });
    $lv->define_enums({ in_contest => { this => $cid } });

    my $ref_count_sql = $lv->visible_cols->{Rc} ? q~
        SELECT COUNT(*) FROM contest_contest_tags CCT2 WHERE CCT2.tag_id = CT.id~ : 'NULL';
    my $c = $dbh->prepare(qq~
        SELECT CT.id, CT.name,
            (SELECT 1 FROM contest_contest_tags CCT1
                WHERE CCT1.tag_id = CT.id AND CCT1.contest_id = ?) AS is_used,
            ($ref_count_sql) AS ref_count
        FROM contest_tags CT WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $c->execute($cid, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit=> url_f('contest_tags_edit', id => $row->{id}),
            href_delete => url_f('contest_tags', 'delete' => $row->{id}),
            href_view_contests => url_f('contests', search => "has_tag($row->{id})"),
        );
    };

    $lv->attach(url_f('contest_tags'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('contest_tags') ], editable => $is_root);
}

sub find_contest_tags_api {
    my ($p) = @_;
    my $r = $dbh->selectall_arrayref(q~
        SELECT CT.id, CT.name FROM contest_tags CT
        WHERE CT.name STARTS WITH ?
        ORDER BY CT.name ROWS 100~, { Slice => {} },
        $p->{query});
    $p->print_json({ suggestions =>
        [ map { value => $_->{name}, data => $_ }, @$r ]
    });
}

1;
