package CATS::UI::Awards;

use strict;
use warnings;

use CATS::DB;
use CATS::Form;
use CATS::Globals qw($cid $is_jury $is_root $t $uid);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;
#use CATS::User;

our $form = CATS::Form->new(
    table => 'awards',
    fields => [
        [ name => 'contest_id', caption => 603, before_save => sub { $cid } ],
        [ name => 'name',
            validators => [ CATS::Field::str_length(1, 200) ], editor => { size => 50 }, caption => 601 ],
        [ name => 'is_public', validators => $CATS::Field::bool, %CATS::Field::default_zero,
            caption => 669 ],
        [ name => 'color',
            validators => [ CATS::Field::str_length(1, 50) ], editor => { size => 10 }, caption => 675 ],
        [ name => 'descr', caption => 620 ],
    ],
    href_action => 'awards_edit',
    descr_field => 'name',
    template_var => 'aw',
    msg_saved => 1231,
    msg_deleted => 1232,
    before_display => sub { $t->param(submenu => [ CATS::References::menu('awards') ]) },
    before_delete => sub { $is_jury },
);

sub awards_edit_frame {
    my ($p) = @_;
    $is_jury or return;
    init_template($p, 'awards_edit');
    $form->edit_frame($p, redirect => [ 'awards' ]);
}

sub awards_frame {
    my ($p) = @_;

    $form->delete_or_saved($p) if $is_jury;

    init_template($p, 'awards');
    my $lv = CATS::ListView->new(web => $p, name => 'awards', url => url_f('awards'));

    $lv->default_sort(0)->define_columns([
        { caption => res_str(601), order_by => 'name', width => '30%' },
        { caption => res_str(675), order_by => 'color', width => '5%', col => 'Cl' },
        { caption => res_str(620), order_by => 'descr', width => '30%', col => 'Ds' },
        ($is_jury ? (
            { caption => res_str(669), order_by => 'is_public', width => '5%', col => 'Pu' },
        ) : ()),
        { caption => res_str(606), order_by => 'user_count', width => '5%', col => 'Uc' },
    ]);
    $lv->define_db_searches([ qw(id name color is_public descr) ]);
    $lv->default_searches([ qw(name) ]);

    my $sth = $dbh->prepare(qq~
        SELECT AW.id, AW.name, AW.is_public, AW.color, AW.descr
        FROM awards AW
        WHERE AW.contest_id = ? ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $descr_prefix_len = 50;
    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            descr_prefix => substr($row->{descr}, 0, $descr_prefix_len),
            descr_cut => length($row->{descr}) > $descr_prefix_len,
            href_edit => $is_jury && url_f('awards_edit', id => $row->{id}),
            href_delete => $is_jury && url_f('awards', 'delete' => $row->{id}),
            href_view_users => url_f('users', search => "has_award($row->{id})"),
        );
    };

    $lv->attach($fetch_record, $sth);

    $t->param(submenu => [ CATS::References::menu('awards') ], editable => $is_jury);
}

1;
