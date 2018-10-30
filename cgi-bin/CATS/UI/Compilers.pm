package CATS::UI::Compilers;

use strict;
use warnings;

use CATS::DB;
use CATS::Form;
use CATS::Globals qw($is_jury $is_root $t);
use CATS::JudgeDB;
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

sub invert { !$_[0] }

my $str1_200 = CATS::Field::str_length(1, 200);
my $str0_200 = CATS::Field::str_length(0, 200);

sub _submenu {
    $t->param(submenu => [ CATS::References::menu('compilers') ]) if $is_jury;
}

our $form = CATS::Form->new(
    table => 'default_de',
    fields => [
        [ name => 'code', validators => [ $str1_200 ], caption => 619, ],
        [ name => 'description', validators => [ $str1_200 ], caption => 620, editor => { size => 80 } ],
        [ name => 'file_ext', validators => [ $str0_200 ], caption => 621, ],
        [ name => 'default_file_ext', validators => [ $str0_200 ], caption => 624, ],
        [ name => 'err_regexp', validators => [ $str0_200 ], caption => 662, ],
        [ name => 'locked', validators => [ qr/^1?$/ ],
            db_name => 'in_contests', after_load => \&invert, before_save => \&invert, caption => 622, ],
        [ name => 'memory_handicap',
            validators => [ CATS::Field::int_range(min => 0, max => 10000, allow_empty => 1) ], caption => 640, ],
        [ name => 'syntax', validators => [ $str0_200 ], caption => 623, ],
    ],
    href_action => 'compilers_edit',
    descr_field => 'description',
    before_commit => \&CATS::JudgeDB::invalidate_de_bitmap_cache,
    template_var => 'cp',
    msg_deleted => 1064,
    msg_saved => 1065,
    before_display => \&_submenu,
);

sub compilers_edit_frame {
    my ($p) = @_;
    init_template($p, 'compilers_edit.html.tt');
    $form->edit_frame($p, readonly => !$is_root, redirect => [ 'compilers' ]);
}

sub compilers_frame {
    my ($p) = @_;

    init_template($p, 'compilers.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'compilers');

    $is_root and $form->delete_or_saved($p,
        before_commit => \&CATS::JudgeDB::invalidate_de_bitmap_cache);

    $lv->define_columns(url_f('compilers'), 0, 0, [
        { caption => res_str(619), order_by => 'code', width => '10%' },
        { caption => res_str(620), order_by => 'description', width => '40%' },
        { caption => res_str(621), order_by => 'file_ext', width => '10%' },
        ($is_root ? (
            { caption => res_str(624), order_by => 'default_file_ext', width => '5%', col => 'De' },
            { caption => res_str(662), order_by => 'err_regexp', width => '10%', col => 'Er' },
        ) : ()),
        { caption => res_str(640), order_by => 'memory_handicap', width => '5%', col => 'Mh' },
        { caption => res_str(623), order_by => 'syntax', width => '10%', col => 'Sy' },
        ($is_jury ? { caption => res_str(622), order_by => 'in_contests', width => '10%' } : ()),
    ]);

    $lv->define_db_searches($form->{sql_fields});

    my ($q, @bind) = $sql->select('default_de', [ 'id as did', @{$form->{sql_fields}} ],
        $is_jury ? $lv->where : { %{$lv->where}, in_contests => 1 });
    my $c = $dbh->prepare("$q " . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            locked => !$row->{in_contests},
            ($is_root ? (
                href_edit => url_f('compilers_edit', id => $row->{did}),
                href_delete => url_f('compilers', 'delete' => $row->{did})) : ()),
        );
    };
    $lv->attach(url_f('compilers'), $fetch_record, $c);
    _submenu;
}

1;
