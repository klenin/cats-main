package CATS::UI::ContactTypes;

use strict;
use warnings;

use Encode;

use CATS::DB;
use CATS::Form;
use CATS::Globals qw($is_jury $is_root $t);
use CATS::JudgeDB;
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

my $str1_200 = CATS::Field::str_length(1, 200);

sub _submenu { $t->param(submenu => [ CATS::References::menu('contact_types') ]); }

our $form = CATS::Form->new(
    table => 'contact_types',
    fields => [
        [ name => 'name', validators => [ CATS::Field::str_length(1, 200) ], caption => 601, ],
        [ name => 'url', validators => [ CATS::Field::str_length(0, 200) ],
            caption => 668, editor => { size => 80 } ],
    ],
    href_action => 'contact_types_edit',
    descr_field => 'name',
    template_var => 'ct',
    msg_deleted => 1069,
    msg_saved => 1070,
    before_display => \&_submenu,
);

sub contact_types_edit_frame {
    my ($p) = @_;
    init_template($p, 'contact_types_edit.html.tt');
    $form->edit_frame($p, readonly => !$is_root, redirect => [ 'contact_types' ]);
}

sub contact_types_frame {
    my ($p) = @_;

    init_template($p, 'contact_types.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'contact_types', url => url_f('contact_types'));

    $is_root and $form->delete_or_saved($p);

    $lv->default_sort(0)->define_columns([
        { caption => res_str(601), order_by => 'name', width => '40%' },
        { caption => res_str(668), order_by => 'url', width => '40%' },
    ]);

    $lv->define_db_searches($form->{sql_fields});

    my ($q, @bind) = $sql->select('contact_types', [ 'id AS ct_id', @{$form->{sql_fields}} ], $lv->where);
    my $sth = $dbh->prepare("$q " . $lv->order_by);
    $sth->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit => url_f('contact_types_edit', id => $row->{ct_id}),
            href_delete => url_f('contact_types', 'delete' => $row->{ct_id}),
        );
    };
    $lv->attach($fetch_record, $sth);
    _submenu;
}

1;
