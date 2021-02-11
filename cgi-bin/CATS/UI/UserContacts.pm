package CATS::UI::UserContacts;

use strict;
use warnings;

use CATS::DB;
use CATS::Form;
use CATS::Globals qw ($is_jury $is_root $t $user);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::User;

sub _check_contact_owner {
    my ($fd, $p) = @_;
    my $aid = $fd->{indexed}->{account_id};
    if ($is_root || !$fd->{id}) {
        $aid->{value} = $p->{uid};
    }
    else {
        my ($old_uid) = $dbh->selectrow_array(q~
            SELECT account_id FROM contacts WHERE id = ?~, undef,
            $fd->{id});
        $old_uid == $user->{id} or return CATS::Messages::msg_debug('Bad account');
        $aid->{value} = $user->{id};
    }
    1;
}

sub _is_profile { $user->{id} && $user->{id} == $_[0]->{uid} }

sub _user_name_and_site {
    my ($p) = @_;
    my ($user_name, $user_site) = _is_profile($p) ? ($user->{name}, $user->{site_id}) :
        @{CATS::User->new->contest_fields([ 'site_id' ])->load($p->{uid}) // {}}{qw(team_name site_id)};
}

our $user_contact_form = CATS::Form->new(
    table => 'contacts',
    fields => [
        [ name => 'account_id' ],
        [ name => 'contact_type_id', validators => [ $CATS::Field::foreign_key ], caption => 642 ],
        [ name => 'handle', validators => [ CATS::Field::str_length(1, 200) ], caption => 657 ],
        [ name => 'is_public', validators => [ qr/^1?$/ ], caption => 669 ],
        [ name => 'is_actual', validators => [ qr/^1?$/ ], caption => 670 ],
    ],
    href_action => 'user_contacts_edit',
    descr_field => 'handle',
    template_var => 'uc',
    msg_saved => 1072,
    msg_deleted => 1071,
    before_display => sub {
        my ($fd, $p) = @_;
        $fd->{contact_types} = $dbh->selectall_arrayref(q~
            SELECT id AS "value", name AS "text" FROM contact_types ORDER BY name~, { Slice => {} });
        unshift @{$fd->{contact_types}}, {};
        my (undef, $user_site) = _user_name_and_site($p);
        $t->param(CATS::User::submenu('user_contacts', $p->{uid}, $user_site));
    },
    validators => [ \&_check_contact_owner ],
);

sub user_contacts_edit_frame {
    my ($p) = @_;
    init_template($p, 'user_contacts_edit.html.tt');
    $is_root || _is_profile($p) or return;
    my @puid = (uid => $p->{uid});
    $user_contact_form->edit_frame($p,
        redirect => [ 'user_contacts', @puid ], href_action_params => \@puid);
}

sub user_contacts_frame {
    my ($p) = @_;

    init_template($p, 'user_contacts');
    $p->{uid} or return;

    my $editable = $is_root || _is_profile($p);
    $user_contact_form->delete_or_saved($p) if $editable;

    my $lv = CATS::ListView->new(web => $p, name => 'user_contacts', url => url_f('user_contacts'));
    my ($user_name, $user_site) = _user_name_and_site($p);
    $user_name or return;

    $lv->default_sort(0)->define_columns([
        { caption => res_str(642), order_by => 'type_name', width => '20%' },
        { caption => res_str(657), order_by => 'handle', width => '30%' },
        ($editable ?
            ({ caption => res_str(669), order_by => 'is_public', width => '15%', col => 'Ip' }) : ()),
        { caption => res_str(670), order_by => 'is_actual', width => '15%', col => 'Ia' },
    ]);
    $lv->define_db_searches($user_contact_form->{sql_fields});
    $lv->default_searches([ qw(handle) ]);

    my $public_cond = $editable ? '' : ' AND C.is_public = 1';
    my $sth = $dbh->prepare(qq~
        SELECT C.id, C.contact_type_id, C.handle, C.is_public, C.is_actual, CT.name AS type_name, CT.url
        FROM contacts C
        INNER JOIN contact_types CT ON CT.id = C.contact_type_id
        WHERE C.account_id = ?$public_cond~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($p->{uid}, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        (
            ($editable ? (
                href_edit => url_f('user_contacts_edit', id => $row->{id}, uid => $p->{uid}),
                href_delete => url_f('user_contacts', 'delete' => $row->{id}, uid => $p->{uid})) : ()),
            %$row,
            ($row->{url} ? (href_contact => sprintf $row->{url}, CATS::Utils::escape_url($row->{handle})) : ()),
        );
    };
    $lv->attach($fetch_record, $sth, { page_params => { uid => $p->{uid} } });
    $t->param(
        CATS::User::submenu('user_contacts', $p->{uid}, $user_site),
        title_suffix => res_str(586),
        problem_title => $user_name,
    );
}

1;
