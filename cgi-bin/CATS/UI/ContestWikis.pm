package CATS::UI::ContestWikis;

use strict;
use warnings;

use CATS::Contest::Utils;
use CATS::DB;
use CATS::Form;
use CATS::Globals qw($cid $is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(res_str);
use CATS::Output qw(init_template url_f);

our $form = CATS::Form->new(
    table => 'contest_wikis',
    fields => [
        [ name => 'contest_id', caption => 603, before_save => sub { $cid } ],
        [ name => 'wiki_id', validators => [ $CATS::Field::foreign_key ], caption => 601, ],
        [ name => 'allow_edit', validators => [ $CATS::Field::bool ], caption => 681, ],
        [ name => 'ordering', validators => [ CATS::Field::int_range(min => 0, max => 100000) ], caption => 682, ],
    ],
    href_action => 'contest_wikis_edit',
    descr_field => 'wiki_id',
    template_var => 'cw',
    msg_deleted => 1073,
    msg_saved => 1074,
    before_display => sub {
        my ($fd, $p) = @_;
        $fd->{wikis} = $dbh->selectall_arrayref(qq~
            SELECT W.id AS "value", W.name AS text
            FROM wiki_pages W
            WHERE W.is_public = 1
            ORDER BY W.name~, { Slice => {} });
        unshift @{$fd->{wikis}}, { value => 0, text => '' };
    },
);

sub contest_wikis_edit_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'contest_wikis_edit.html.tt');
    $form->edit_frame($p, redirect => [ 'contest_wikis' ]);
}

sub contest_wikis_frame {
    my ($p) = @_;

    init_template($p, 'contest_wikis.html.tt');
    $is_jury or return;

    $form->delete_or_saved($p);

    my $lv = CATS::ListView->new(web => $p, name => 'contest_wikis');

    $lv->define_columns(url_f('contest_wikis'), 0, 0, [
        { caption => res_str(601), order_by => 'name', width => '70%' },
        { caption => res_str(681), order_by => 'allow_edit', width => '15%', col => 'Ae' },
        { caption => res_str(682), order_by => 'ordering', width => '15%', col => 'Or' },
    ]);
    #$lv->define_db_searches($form->{sql_fields});
    my $sth = $dbh->prepare(q~
        SELECT CW.id, CW.wiki_id, CW.allow_edit, CW.ordering, W.name
        FROM contest_wikis CW
        INNER JOIN wiki_pages W ON W.id = CW.wiki_id
        WHERE CW.contest_id = ?~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        (
            %$row,
            href_edit => url_f('contest_wikis_edit', id => $row->{id}),
            href_delete => url_f('contest_wikis', 'delete' => $row->{id}),
        );
    };
    $lv->attach(url_f('contest_wikis'), $fetch_record, $sth);
    CATS::Contest::Utils::contest_submenu('contest_wikis');
    $t->param(title_suffix => res_str(589));
}

1;
