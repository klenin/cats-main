package CATS::UI::Keywords;

use strict;
use warnings;

use CATS::DB;
use CATS::Form;
use CATS::Globals qw($is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

my @field_common = (validators => [ CATS::Field::str_length(1, 200) ], editor => { size => 50 });

our $form = CATS::Form->new(
    table => 'keywords',
    fields => [
        [ name => 'code', @field_common, caption => 625 ],
        [ name => 'name_ru', @field_common, caption => 636, ],
        [ name => 'name_en', @field_common, caption => 637, ],
    ],
    href_action => 'keywords_edit',
    descr_field => 'code',
    template_var => 'kw',
    msg_saved => 1174,
    msg_deleted => 1175,
    before_display => sub { $t->param(submenu => [ CATS::References::menu('keywords') ]) },
);

sub keywords_edit_frame {
    my ($p) = @_;
    init_template($p, 'keywords_edit.html.tt');
    $form->edit_frame($p, readonly => !$is_root, redirect => [ 'keywords' ]);
}

sub _has_kw { (search => join ',', map "has_kw($_)", @_) }

sub keywords_frame {
    my ($p) = @_;

    $form->delete_or_saved($p) if $is_root;

    my @search_link = ($is_jury ? (link => 1) : ());
    if ($p->{search_selected} && @{$p->{sel}}) {
        return $p->redirect(url_f('problems_all', _has_kw(@{$p->{sel}}), @search_link));
    }

    init_template($p, 'keywords.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'keywords', url => url_f('keywords'));

    $lv->default_sort(0)->define_columns([
        { caption => res_str(625), order_by => 'code', width => '30%' },
        { caption => res_str(636), order_by => 'name_ru', width => '30%' },
        { caption => res_str(637), order_by => 'name_en', width => '30%' },
        { caption => res_str(643), order_by => 'ref_count', width => '10%', col => 'Rc' },
    ]);
    $lv->define_db_searches([ qw(K.id code name_ru name_en) ]);

    my $ref_count_sql = $lv->visible_cols->{Rc} ? q~
        SELECT COUNT(*) FROM problem_keywords PK WHERE PK.keyword_id = K.id~ : 'NULL';
    my $sth = $dbh->prepare(qq~
        SELECT K.id AS kwid, K.code, K.name_ru, K.name_en, ($ref_count_sql) AS ref_count
        FROM keywords K WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit=> url_f('keywords_edit', id => $row->{kwid}),
            href_delete => url_f('keywords', 'delete' => $row->{kwid}),
            href_view_problems => url_f('problems_all', _has_kw($row->{kwid}), @search_link),
        );
    };

    $lv->attach($fetch_record, $sth);

    $t->param(submenu => [ CATS::References::menu('keywords') ], editable => $is_root) if $is_jury;
}

1;
