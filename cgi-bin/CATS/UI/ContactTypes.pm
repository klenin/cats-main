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

sub fields() {qw(name url)}

my $form = CATS::Form->new({
    table => 'contact_types',
    fields => [ map +{ name => $_ }, fields() ],
    templates => { edit_frame => 'contact_types_edit.html.tt' },
    href_action => 'contact_types',
});

sub contact_types_frame {
    my ($p) = @_;

    $is_root && ($p->{new} || $p->{edit}) and return $form->edit_frame($p);

    my $lv = CATS::ListView->new(name => 'contact_types', template => 'contact_types.html.tt');

    $is_root and $form->edit_delete(id => $p->{delete}, descr => 'name', msg => 1069);
    $is_root && $p->{edit_save} and
        $form->edit_save($p) and msg(1070, Encode::decode_utf8($p->{name}));

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
