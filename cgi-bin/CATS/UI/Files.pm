package CATS::UI::Files;

use strict;
use warnings;

use File::Copy qw();

use CATS::BinaryFile;
use CATS::DB;
use CATS::Form;
use CATS::Globals qw($cid $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(downloads_path downloads_url init_template url_f);
use CATS::References;
use CATS::User;

my @str_1_200 = (validators => [ CATS::Field::str_length(1, 200) ]);

our $form = CATS::Form->new(
    table => 'files',
    fields => [
        [ name => 'name', @str_1_200, editor => { size => 50 }, caption => 601 ],
        [ name => 'description', caption => 620 ],
        [ name => 'guid', validators => [ qr/^[a-zA-Z0-9\.]{0,50}$/ ],
            editor => { size => 50 }, caption => 619, ],
        [ name => 'file_size', caption => 684, ],
    ],
    href_action => 'files_edit',
    descr_field => 'name',
    template_var => 'f',
    msg_saved => 1195,
    msg_deleted => 1196,
    before_display => sub { $t->param(submenu => [ CATS::References::menu('files') ]) },
    before_save => sub {
        my ($fd, $p) = @_;
        my $f = $p->{file} or return;
        my ($ext) = $f->remote_file_name =~ /(\.[a-zA-Z0-9]+)$/;
        my $fn = $fd->{indexed}->{guid}->{value} ||= CATS::User::make_sid . ($ext || '');
        $fd->{indexed}->{file_size}->{value} = -s $f->local_file_name;
        File::Copy::move($f->local_file_name, downloads_path . "f/$fn") or die $!;
    },
    before_save_db => sub {
        $_[0]->{file_size} ne '' or delete $_[0]->{file_size};
    },
);

sub files_edit_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'files_edit.html.tt');
    $form->edit_frame($p, redirect => [ 'files' ]);
}

sub files_frame {
    my ($p) = @_;

    $is_root or return;
    $form->delete_or_saved($p) if $is_root;
    init_template($p, 'files.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'files');

    $lv->define_columns(url_f('v'), 0, 0, [
        { caption => res_str(601), order_by => 'name', width => '20%' },
        { caption => res_str(619), order_by => 'guid', width => '30%' },
        { caption => res_str(620), order_by => 'description', width => '30%', col => 'De' },
        { caption => res_str(684), order_by => 'file_size', width => '20%', col => 'Fs' },
    ]);
    $lv->define_db_searches([ qw(id name guid description file_size) ]);

    my $c = $dbh->prepare(qq~
        SELECT
            F.id, F.name, F.file_size, F.guid,
            SUBSTRING(F.description FROM 1 FOR 100) as description,
            OCTET_LENGTH(F.description) AS description_len
        FROM files F WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $c->execute($lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit=> url_f('files_edit', id => $row->{id}),
            href_delete => url_f('files', 'delete' => $row->{id}),
            href_download => downloads_url . "/f/$row->{guid}",
        );
    };

    $lv->attach(url_f('files'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('files') ], editable => $is_root);
}

1;
