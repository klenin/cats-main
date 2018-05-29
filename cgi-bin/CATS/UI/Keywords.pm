package CATS::UI::Keywords;

use strict;
use warnings;

use CATS::DB;
use CATS::Form;
use CATS::Globals qw($t $is_jury $is_root);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

sub fields () { qw(name_ru name_en code) }

my $form = CATS::Form->new({
    table => 'keywords',
    fields => [ map +{ name => $_ }, fields() ],
    templates => { edit_frame => 'keywords_edit.html.tt' },
    href_action => 'keywords',
});

sub edit_save {
    my ($p) = @_;
    ($p->{name_en} // '') ne '' && 0 == grep(length $p->{$_} > 200, fields())
        or return msg(1084);
    $form->edit_save($p);
}

sub keywords_frame {
    my ($p) = @_;

    if ($is_root) {
        $form->edit_delete(id => $p->{delete});
        $p->{new} || $p->{edit} and return $form->edit_frame($p);
    }
    init_template($p, 'keywords.html.tt');
    my $lv = CATS::ListView->new(name => 'keywords');

    $is_root && $p->{edit_save} and edit_save($p);

    $lv->define_columns(url_f('keywords'), 0, 0, [
        { caption => res_str(625), order_by => '2', width => '30%' },
        { caption => res_str(636), order_by => '3', width => '30%' },
        { caption => res_str(637), order_by => '4', width => '30%' },
        { caption => res_str(643), order_by => '5', width => '10%' },
    ]);
    $lv->define_db_searches([ qw(K.id code name_ru name_en) ]);

    my $c = $dbh->prepare(q~
        SELECT k.id AS kwid, k.code, k.name_ru, k.name_en,
            (SELECT COUNT(*) FROM problem_keywords pk WHERE pk.keyword_id = k.id) AS ref_count
        FROM keywords k WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $c->execute($lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit=> url_f('keywords', edit => $row->{kwid}),
            href_delete => url_f('keywords', 'delete' => $row->{kwid}),
            href_view_problems => url_f('problems_all', kw => $row->{kwid}, ($is_jury ? (link => 1) : ())),
        );
    };

    $lv->attach(url_f('keywords'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('keywords') ], editable => $is_root) if $is_jury;
}

1;
