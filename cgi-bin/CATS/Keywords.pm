package CATS::Keywords;

use strict;
use warnings;

use CATS::Web qw(param url_param);
use CATS::DB;
use CATS::Misc qw(
    $t $is_jury $is_root
    init_template init_listview_template msg res_str url_f
    order_by define_columns attach_listview references_menu);

sub keywords_fields () { qw(name_ru name_en code) }

sub keywords_new_frame
{
    init_template('keywords_new.html.tt');
    $t->param(href_action => url_f('keywords'));
}

sub keywords_new_save
{
    my %p = map { $_ => (param($_) || '') } keywords_fields();

    $p{name_en} ne '' && 0 == grep length $p{$_} > 200, keywords_fields()
        or return msg(84);

    my $field_names = join ', ', keywords_fields();
    $dbh->do(qq~
        INSERT INTO keywords (id, $field_names) VALUES (?, ?, ?, ?)~, {},
        new_id, @p{keywords_fields()});
    $dbh->commit;
}

sub keywords_edit_frame
{
    init_template('keywords_edit.html.tt');

    my $kwid = url_param('edit');
    my $kw = $dbh->selectrow_hashref(qq~SELECT * FROM keywords WHERE id=?~, {}, $kwid);
    $t->param(%$kw, href_action => url_f('keywords'));
}

sub keywords_edit_save
{
    my $kwid = param('id');
    my %p = map { $_ => (param($_) || '') } keywords_fields();

    $p{name_en} ne '' && 0 == grep(length $p{$_} > 200, keywords_fields())
        or return msg(84);

    my $set = join ', ', map "$_ = ?", keywords_fields();
    $dbh->do(qq~
        UPDATE keywords SET $set WHERE id = ?~, {},
        @p{keywords_fields()}, $kwid);
    $dbh->commit;
}

sub keywords_frame
{
    if ($is_root) {
        if (defined url_param('delete')) {
            my $kwid = url_param('delete');
            $dbh->do(qq~DELETE FROM keywords WHERE id = ?~, {}, $kwid);
            $dbh->commit;
        }

        defined url_param('new') and return keywords_new_frame;
        defined url_param('edit') and return keywords_edit_frame;
    }
    init_listview_template('keywords', 'keywords', 'keywords.html.tt');

    $is_root && defined param('new_save') and keywords_new_save;
    $is_root && defined param('edit_save') and keywords_edit_save;

    define_columns(url_f('keywords'), 0, 0, [
        { caption => res_str(625), order_by => '2', width => '31%' },
        { caption => res_str(636), order_by => '3', width => '31%' },
        { caption => res_str(637), order_by => '4', width => '31%' },
    ]);

    my $c = $dbh->prepare(qq~
        SELECT id, code, name_ru, name_en FROM keywords ~.order_by);
    $c->execute;

    my $fetch_record = sub {
        my ($kwid, $code, $name_ru, $name_en) = $_[0]->fetchrow_array
            or return ();
        return (
            editable => $is_root,
            kwid => $kwid, code => $code, name_ru => $name_ru, name_en => $name_en,
            href_edit=> url_f('keywords', edit => $kwid),
            href_delete => url_f('keywords', 'delete' => $kwid),
            href_view_problems => url_f('problems', kw => $kwid),
        );
    };

    attach_listview(url_f('keywords'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('keywords') ], editable => $is_root) if $is_jury;
}

1;
