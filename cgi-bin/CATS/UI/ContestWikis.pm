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

my $ordering = CATS::Field::int_range(min => 0, max => 100000);

our $form = CATS::Form->new(
    table => 'contest_wikis',
    fields => [
        [ name => 'contest_id', caption => 603, before_save => sub { $cid } ],
        [ name => 'wiki_id', validators => [ $CATS::Field::foreign_key ], caption => 601, ],
        [ name => 'allow_edit', validators => [ $CATS::Field::bool ], caption => 681, ],
        [ name => 'ordering', validators => [ $ordering ], caption => 682, ],
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
        $fd->{indexed}->{allow_edit}->{readonly} = !$is_root;
    },
    validators => [ sub {
        my ($fd, $p) = @_;
        my $wiki_id = $fd->{indexed}->{wiki_id};
        $dbh->selectrow_array(q~
            SELECT id FROM wiki_pages
            WHERE id = ? AND is_public = 1~, undef,
            $wiki_id->{value}) or return ($wiki_id->{error} = res_str(1078) and undef);
        return 1 if $is_root;
        if (!$fd->{id}) {
            $fd->{indexed}->{allow_edit}->{value} = 0;
            return 1;
        }
        my ($old_wiki_id, $old_allow_edit) = $dbh->selectrow_array(q~
            SELECT wiki_id, allow_edit FROM contest_wikis WHERE id = ?~, undef,
            $fd->{id});
        $fd->{indexed}->{allow_edit}->{value} = $old_allow_edit;
        return ($wiki_id->{error} = res_str(1078) and undef)
            if $old_allow_edit && $old_wiki_id != $wiki_id->{value};
        1;
    }, ],
);

sub contest_wikis_edit_frame {
    my ($p) = @_;
    init_template($p, 'contest_wikis_edit.html.tt');
    $is_jury or return;
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
