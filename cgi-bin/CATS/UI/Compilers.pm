package CATS::UI::Compilers;

use strict;
use warnings;

use Encode;

use CATS::DB;
use CATS::Form;
use CATS::JudgeDB;
use CATS::ListView;
use CATS::Misc qw(
    $t $is_jury $is_root
    init_template msg res_str url_f references_menu);
use CATS::Web qw(param param_on url_param);

sub fields() {qw(code description file_ext default_file_ext in_contests memory_handicap syntax)}

my $form = CATS::Form->new({
    table => 'default_de',
    fields => [ map +{ name => $_ }, fields() ],
    templates => { edit_frame => 'compilers_edit.html.tt' },
    href_action => 'compilers',
});

sub edit_frame {
    $form->edit_frame(sub { $_[0]->{locked} = !$_[0]->{in_contests} });
}

sub edit_save {
    CATS::JudgeDB::invalidate_de_bitmap_cache;
    $form->edit_save(sub { $_[0]->{in_contests} = !param_on('locked') })
        and msg(1065, Encode::decode_utf8(param('description')));
}

sub compilers_frame {
    if ($is_jury) {
        defined url_param('new') || defined url_param('edit') and return edit_frame;
    }

    my $lv = CATS::ListView->new(name => 'compilers', template => 'compilers.html.tt');

    if ($is_root && defined url_param('delete')) { # extra security
        my $deid = url_param('delete');
        if (my ($descr) = $dbh->selectrow_array(q~
            SELECT description FROM default_de WHERE id = ?~, undef,
            $deid)
        ) {
            $dbh->do(q~
                DELETE FROM default_de WHERE id = ?~, undef,
                $deid);
            CATS::JudgeDB::invalidate_de_bitmap_cache;
            $dbh->commit;
            msg(1064, $descr);
        }
    }
    $is_jury && defined param('edit_save') and edit_save;

    $lv->define_columns(url_f('compilers'), 0, 0, [
        { caption => res_str(619), order_by => '2', width => '10%' },
        { caption => res_str(620), order_by => '3', width => '40%' },
        { caption => res_str(621), order_by => '4', width => '10%' },
        ($is_root ? { caption => res_str(624), order_by => '5', width => '10%' } : ()),
        { caption => res_str(640), order_by => '7', width => '10%' },
        { caption => res_str(623), order_by => '8', width => '10%' },
        ($is_jury ? { caption => res_str(622), order_by => '5', width => '10%' } : ()),
    ]);

    $lv->define_db_searches([ fields() ]);

    my ($q, @bind) = $sql->select('default_de', [ 'id as did', fields() ],
        $is_jury ? $lv->where : { %{$lv->where}, in_contests => 1 });
    my $c = $dbh->prepare("$q " . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            locked => !$row->{in_contests},
            href_edit => url_f('compilers', edit => $row->{did}),
            href_delete => url_f('compilers', 'delete' => $row->{did}));
    };
    $lv->attach(url_f('compilers'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('compilers') ], editable => $is_root, is_jury => $is_jury)
        if $is_jury;
}

1;
