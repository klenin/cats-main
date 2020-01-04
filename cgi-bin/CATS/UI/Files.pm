package CATS::UI::Files;

use strict;
use warnings;

use File::Copy qw();

use CATS::DB;
use CATS::Form;
use CATS::Globals qw($cid $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(downloads_path downloads_url init_template url_f);
use CATS::References;
use CATS::User;

my @str_1_200 = (validators => [ CATS::Field::str_length(1, 200) ]);

sub guid_to_fn { downloads_path . "f/$_[0]" }
sub unlink_guid {
    my $fn = guid_to_fn($_[0]);
    unlink $fn or die $! if -f $fn;
}

sub _remove_old_guid {
    my ($fd, $p) = @_;
    $fd->{id} or return;
    my $guid = $fd->{indexed}->{guid}->{value};
    my ($old_guid) = $dbh->selectrow_array(q~
        SELECT guid FROM files WHERE id = ?~, undef,
        $fd->{id}) or return;
    $old_guid ne $guid or return;
    if ($p->{file}) {
        unlink_guid($old_guid);
    }
    else {
        my $old_fn = guid_to_fn($old_guid);
        File::Copy::move($old_fn, guid_to_fn($guid)) or die $! if -f $old_fn;
    }
}

sub _upload_file {
    my ($fd, $p) = @_;
    my $f = $p->{file} or return;
    my ($ext) = $f->remote_file_name =~ /(\.[a-zA-Z0-9]+)$/;
    my $guid = $fd->{indexed}->{guid}->{value} ||= CATS::User::make_sid . ($ext || '');
    $fd->{indexed}->{file_size}->{value} = -s $f->local_file_name;
    File::Copy::move($f->local_file_name, guid_to_fn($guid)) or die $!;
}

our $form = CATS::Form->new(
    table => 'files',
    fields => [
        [ name => 'name', @str_1_200, editor => { size => 50 }, caption => 601 ],
        [ name => 'description', caption => 620 ],
        [ name => 'guid', validators => [ qr/^[a-zA-Z0-9\.]{0,50}$/ ],
            editor => { size => 50 }, caption => 619, ],
        [ name => 'file_size', caption => 684, ],
        [ name => 'last_modified', before_save => sub { \'CURRENT_TIMESTAMP' } ],
    ],
    href_action => 'files_edit',
    descr_field => 'name, guid',
    template_var => 'f',
    msg_saved => 1195,
    msg_deleted => 1196,
    before_display => sub { $t->param(submenu => [ CATS::References::menu('files') ]) },
    validators => [ CATS::Field::unique('guid') ],
    before_save => sub {
        _remove_old_guid(@_);
        _upload_file(@_);
    },
    after_delete => sub {
        my ($p, $id, %rest) = @_;
        if (my $guid = $rest{descr}->[1]) {
            unlink_guid($guid);
        }
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
    my $lv = CATS::ListView->new(web => $p, name => 'files', url => url_f('files'));

    $lv->default_sort(0)->define_columns([
        { caption => res_str(601), order_by => 'name', width => '20%' },
        { caption => res_str(619), order_by => 'guid', width => '25%' },
        { caption => res_str(620), order_by => 'description', width => '25%', col => 'De' },
        { caption => res_str(684), order_by => 'file_size', width => '15%', col => 'Fs' },
        { caption => res_str(634), order_by => 'last_modified', width => '15%', col => 'Lm' },
    ]);
    $lv->define_db_searches([ qw(id name guid description file_size) ]);

    my $sth = $dbh->prepare(qq~
        SELECT
            F.id, F.name, F.file_size, F.guid, F.last_modified,
            SUBSTRING(F.description FROM 1 FOR 100) as description,
            OCTET_LENGTH(F.description) AS description_len
        FROM files F WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit=> url_f('files_edit', id => $row->{id}),
            href_delete => url_f('files', 'delete' => $row->{id}),
            href_download => downloads_url . "f/$row->{guid}",
        );
    };

    $lv->attach($fetch_record, $sth);

    $t->param(submenu => [ CATS::References::menu('files') ], editable => $is_root);
}

1;
