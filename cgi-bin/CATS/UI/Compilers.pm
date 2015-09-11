package CATS::UI::Compilers;

use strict;
use warnings;

use CATS::Web qw(param param_on url_param);
use CATS::DB;
use CATS::Misc qw(
    $t $is_jury $is_root
    init_template init_listview_template msg res_str url_f
    order_by define_columns attach_listview references_menu);

sub fields() {qw(code description file_ext default_file_ext in_contests memory_handicap syntax)}

sub edit_frame
{
    init_template('compilers_edit.html.tt');

    my $id = url_param('edit');

    my $field_values = $id ? CATS::DB::select_row('default_de', [ fields() ], { id => $id }) : {};

    $t->param(
        id => $id,
        %$field_values,
        locked => !$field_values->{in_contests},
        href_action => url_f('compilers'));
}

sub edit_save
{
    my %params;
    $params{$_} = param($_) for fields();
    $params{in_contests} = !param_on('locked');
    my $id = param('id');

    if ($id) {
        $dbh->do(_u $sql->update('default_de', \%params, { id => $id }));
    }
    else {
        $params{id} = new_id;
        $dbh->do(_u $sql->insert('default_de', \%params, { id => $id }));
    }
    $dbh->commit;
}

sub compilers_frame
{
    if ($is_jury) {
        if ($is_root && defined url_param('delete')) { # extra security
            my $deid = url_param('delete');
            $dbh->do(qq~DELETE FROM default_de WHERE id = ?~, {}, $deid);
            $dbh->commit;
        }

        defined url_param('new') || defined url_param('edit') and return edit_frame;
    }

    init_listview_template('compilers', 'compilers', 'compilers.html.tt');

    $is_jury && defined param('edit_save') and edit_save;

    define_columns(url_f('compilers'), 0, 0, [
        { caption => res_str(619), order_by => '2', width => '10%' },
        { caption => res_str(620), order_by => '3', width => '40%' },
        { caption => res_str(621), order_by => '4', width => '10%' },
        ($is_root ? { caption => res_str(624), order_by => '5', width => '10%' } : ()),
        { caption => res_str(640), order_by => '7', width => '10%' },
        { caption => res_str(623), order_by => '8', width => '10%' },
        ($is_jury ? { caption => res_str(622), order_by => '5', width => '10%' } : ()),
    ]);

    my ($q, @bind) = $sql->select('default_de', [ 'id as did', fields() ], $is_jury ? {} : { in_contests => 1 });
    my $c = $dbh->prepare("$q " . order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            locked => !$row->{in_contests},
            href_edit => url_f('compilers', edit => $row->{did}),
            href_delete => url_f('compilers', 'delete' => $row->{did}));
    };
    attach_listview(url_f('compilers'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('compilers') ], editable => $is_root)
        if $is_jury;
}

1;
