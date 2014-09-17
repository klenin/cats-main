package CATS::Compilers;

use strict;
use warnings;

use CATS::Web qw(param url_param);
use CATS::DB;
use CATS::Misc qw(
    $t $is_jury $is_root
    init_template init_listview_template msg res_str url_f
    order_by define_columns attach_listview references_menu);
use CATS::Utils qw(param_on);

sub edit_frame
{
    init_template('compilers_edit.html.tt');

    my $id = url_param('edit');

    my ($code, $description, $supported_ext, $in_contests, $memory_handicap, $syntax) =
        $id ? $dbh->selectrow_array(q~
            SELECT code, description, file_ext, in_contests, memory_handicap, syntax
            FROM default_de WHERE id = ?~, {},
            $id) : ();

    $t->param(
        id => $id,
        code => $code,
        description => $description,
        supported_ext => $supported_ext,
        locked => !$in_contests,
        memory_handicap => $memory_handicap,
        syntax => $syntax,
        href_action => url_f('compilers'));
}

sub edit_save
{
    my $code = param('code');
    my $description = param('description');
    my $supported_ext = param('supported_ext');
    my $locked = param_on('locked');
    my $memory_handicap = param('memory_handicap');
    my $syntax = param('syntax');
    my $id = param('id');

    if ($id) {
        $dbh->do(q~
            UPDATE default_de
            SET code = ?, description = ?, file_ext = ?, in_contests = ?,
                memory_handicap = ?, syntax = ?
            WHERE id = ?~, undef,
            $code, $description, $supported_ext, !$locked, $memory_handicap, $syntax, $id);
        $dbh->commit;
    }
    else {
        $dbh->do(q~
            INSERT INTO default_de(id, code, description, file_ext, in_contests, memory_handicap, syntax)
            VALUES(?, ?, ?, ?, ?, ?, ?)~, undef,
            new_id, $code, $description, $supported_ext, !$locked, $memory_handicap, $syntax);
        $dbh->commit;
    }
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
        { caption => res_str(621), order_by => '4', width => '20%' },
        { caption => res_str(640), order_by => '6', width => '15%' },
        { caption => res_str(623), order_by => '7', width => '10%' },
        ($is_jury ? { caption => res_str(622), order_by => '5', width => '10%' } : ())
    ]);

    my $where = $is_jury ? '' : ' WHERE in_contests = 1';
    my $c = $dbh->prepare(qq~
        SELECT id, code, description, file_ext, in_contests, memory_handicap, syntax
        FROM default_de$where ~.order_by);
    $c->execute;

    my $fetch_record = sub {
        my ($did, $code, $description, $supported_ext, $in_contests, $memory_handicap, $syntax) =
            $_[0]->fetchrow_array
            or return ();
        return (
            editable => $is_root, did => $did, code => $code,
            description => $description,
            supported_ext => $supported_ext,
            memory_handicap => $memory_handicap,
            syntax => $syntax,
            locked => !$in_contests,
            href_edit => url_f('compilers', edit => $did),
            href_delete => url_f('compilers', 'delete' => $did));
    };
    attach_listview(url_f('compilers'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('compilers') ], editable => $is_root)
        if $is_jury;
}

1;
