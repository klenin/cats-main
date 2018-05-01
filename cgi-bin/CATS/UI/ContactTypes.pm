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
use CATS::Web qw(param url_param);

sub fields() {qw(name url)}

my $form = CATS::Form->new({
    table => 'contact_types',
    fields => [ map +{ name => $_ }, fields() ],
    templates => { edit_frame => 'contact_types_edit.html.tt' },
    href_action => 'contact_types',
});

sub edit_frame { $form->edit_frame({}); }

sub edit_save {
    $form->edit_save({}) and msg(1070, Encode::decode_utf8(param('name')));
}

sub contact_types_frame {
    if ($is_root) {
        defined url_param('new') || defined url_param('edit') and return edit_frame;
    }

    my $lv = CATS::ListView->new(name => 'contact_types', template => 'contact_types.html.tt');

    $is_root and $form->edit_delete(id => url_param('delete') // 1, descr => 'name', msg => 1069);
    $is_root && defined param('edit_save') and edit_save;

    $lv->define_columns(url_f('contact_types'), 0, 0, [
        { caption => res_str(601), order_by => 'name', width => '40%' },
        { caption => res_str(668), order_by => 'url', width => '40%' },
    ]);

    $lv->define_db_searches([ fields() ]);

    my ($q, @bind) = $sql->select('contact_types', [ 'id AS ct_id', fields() ], $lv->where);
    my $c = $dbh->prepare("$q " . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit => url_f('contact_types', edit => $row->{ct_id}),
            href_delete => url_f('contact_types', 'delete' => $row->{ct_id}),
        );
    };
    $lv->attach(url_f('contact_types'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('contact_types') ]);
}

1;
