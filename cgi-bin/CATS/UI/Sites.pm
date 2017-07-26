package CATS::UI::Sites;

use strict;
use warnings;

use Encode;

use CATS::DB;
use CATS::Form qw(validate_string_length);
use CATS::ListView;
use CATS::Misc qw(
    $t $is_jury $is_root
    init_template msg res_str url_f);
use CATS::References;
use CATS::Web qw(param url_param);

sub fields() {qw(name region city org_name address)}

my $form = CATS::Form->new({
    table => 'sites',
    fields => [ map +{ name => $_ }, fields ],
    templates => { edit_frame => 'sites_edit.html.tt' },
    href_action => 'sites',
});

sub edit_frame {
    $form->edit_frame;
}

sub edit_save {
    validate_string_length(param('name'), 601, 1, 100) or return;
    $form->edit_save()
        and msg(1067, Encode::decode_utf8(param('name')));
}

sub sites_frame {
    $is_root or return;
    defined url_param('new') || defined url_param('edit') and return edit_frame;

    my $lv = CATS::ListView->new(name => 'sites', template => 'sites.html.tt');

    if (defined url_param('delete')) {
        my $site_id = url_param('delete');
        if (my ($name) = $dbh->selectrow_array(q~
            SELECT name FROM sites WHERE id = ?~, undef,
            $site_id)
        ) {
            $dbh->do(q~
                DELETE FROM sites WHERE id = ?~, undef,
                $site_id);
            $dbh->commit;
            msg(1066, $name);
        }
    }
    defined param('edit_save') and edit_save;

    $lv->define_columns(url_f('sites'), 0, 0, [
        { caption => res_str(601), order_by => '2', width => '20%' },
        { caption => res_str(654), order_by => '3', width => '15%' },
        { caption => res_str(655), order_by => '4', width => '15%' },
        { caption => res_str(656), order_by => '7', width => '20%' },
        { caption => res_str(657), order_by => '8', width => '30%' },
    ]);

    $lv->define_db_searches([ fields() ]);

    my ($q, @bind) = $sql->select('sites', [ 'id', fields ],
        $is_jury ? $lv->where : { %{$lv->where}, in_contests => 1 });
    my $c = $dbh->prepare("$q " . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit => url_f('sites', edit => $row->{id}),
            href_delete => url_f('sites', 'delete' => $row->{id})
        );
    };
    $lv->attach(url_f('sites'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('sites') ], editable => $is_root)
        if $is_jury;
}

1;
