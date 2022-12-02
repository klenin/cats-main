package CATS::User;

use strict;
use warnings;

use Encode;
use Storable;

use CATS::Config;
use CATS::Constants;
use CATS::Contest::Participate qw(get_registered_contestant is_jury_in_contest);
use CATS::Countries;
use CATS::DB qw(:DEFAULT $db);
use CATS::Form qw(validate_fixed_point validate_integer validate_string_length);
use CATS::Globals qw($cid $is_jury $is_root $t $uid $user);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(search url_f);
use CATS::Privileges;
use CATS::RankTable::Cache;
use CATS::Settings qw($settings);

my $hash_password;
BEGIN {
    $hash_password = eval { require Authen::Passphrase::BlowfishCrypt; } ?
        sub {
            my $octets = Encode::is_utf8($_[0]) ? Encode::encode_utf8($_[0]) : $_[0];
            Authen::Passphrase::BlowfishCrypt->new(
                cost => 8, salt_random => 1, passphrase => $octets)->as_rfc2307;
        } :
        sub { $_[0] }
}

sub hash_password { $hash_password->(@_); }

sub param_names () {qw(
    login team_name capitan_name country motto restrict_ips
    city tz_offset affiliation affiliation_year
    git_author_name git_author_email
)}

sub new {
    my ($class) = @_;
    $class = ref $class if ref $class;
    my $self = {};
    bless $self, $class;
    $self;
}

sub parse_params {
    my ($self, $p) = @_;
    $self->{$_} = $p->{$_} || '' for param_names(), qw(password1 password2);
    $self;
}

sub contest_fields {
    my ($self, $fields, $contest_id) = @_;
    $self->{contest_fields} = $fields or die;
    $self->{contest_id} = $contest_id // $cid;
    $self;
}

sub load {
    my ($self, $id, $extra_fields) = @_;
    my @fields = (param_names(), @{$extra_fields || []}, @{$self->{contest_fields} || []});
    my $fields_sql = join(', ' => @fields);
    my $contest_accounts_join = $self->{contest_id} ?
        'LEFT JOIN contest_accounts CA ON CA.account_id = A.id AND CA.contest_id = ?' : '';
    @$self{@fields} = $dbh->selectrow_array(qq~
        SELECT $fields_sql
        FROM accounts A
        $contest_accounts_join
        WHERE A.id = ?~, { Slice => {} },
        ($self->{contest_id} // ()), $id
    ) or return;
    $self->{country} ||= $CATS::Countries::countries[0]->{id};
    $self->{settings} = eval { Storable::thaw($self->{frozen_settings} = $self->{settings}) } // {}
        if $self->{settings};
    $_->{selected} = $_->{id} eq $self->{country} for @CATS::Countries::countries;
    $self;
}

sub values { @{$_[0]}{param_names()} }

sub add_to_contest {
    my %p = @_;
    $p{contest_id} && $p{account_id} or die;
    $dbh->do(_u $sql->insert('contest_accounts', {
        id => new_id, contest_id => $p{contest_id}, account_id => $p{account_id}, site_id => $p{site_id},
        is_jury => $p{is_jury} || 0, is_pop => 0, is_hidden => $p{is_hidden} || 0, is_ooc => $p{is_ooc} || 0,
        is_remote => $p{is_remote} || 0, is_site_org => $p{is_site_org} || 0,
        is_virtual => 0, diff_time => 0,
    }));
}

sub generate_login {
    my $login_num = $db->next_sequence_value('login_seq');
    return "team$login_num";
}

sub any_official_contest_by_team {
    my ($account_id) = @_;
    $dbh->selectrow_array(qq~
        SELECT C.title FROM contests C
            INNER JOIN contest_accounts CA ON CA.contest_id = C.id
            INNER JOIN accounts A ON A.id = CA.account_id
            WHERE C.is_official = 1 AND CA.is_ooc = 0 AND CA.is_jury = 0 AND
            C.finish_date < CURRENT_TIMESTAMP AND A.id = ? $db->{LIMIT} 1~, undef,
        $account_id);
}

sub validate_params {
    my ($self, %p) = @_;

    validate_string_length($self->{login}, 616, 1, 50) or return;
    validate_string_length($self->{team_name}, 800, 1, 100) or return;
    validate_string_length($self->{capitan_name}, 801, 0, 100) or return;
    validate_string_length($self->{motto}, 802, 0, 100) or return;
    validate_string_length($self->{affiliation}, 807, 0, 100) or return;
    validate_integer($self->{affiliation_year}, 808, allow_empty => 1, min => 1900, max => 2100) or return;
    validate_fixed_point($self->{tz_offset}, 686, allow_empty => 1) or return;
    $self->{affiliation_year} or $self->{affiliation_year} = undef;
    $self->{tz_offset} or $self->{tz_offset} = undef;

    if ($p{validate_password}) {
        validate_string_length($self->{password1}, 806, 1, 72) or return;
        $self->{password1} eq $self->{password2}
            or return msg(1033);
    }

    my $old_login = '';
    if ($p{id} && !$p{allow_official_rename}) {
        ($old_login, my $old_team_name) = $dbh->selectrow_array(q~
            SELECT login, team_name FROM accounts WHERE id = ?~, undef,
            $p{id});
        if ((($old_team_name // '') ne $self->{team_name}) &&
            (my ($official_contest) = any_official_contest_by_team($p{id})))
        {
            # If the team participated in the official contest, forbid it to rename itself.
            return msg(1086, $official_contest);
        }
    }

    return $old_login eq $self->{login} || $self->validate_login($p{id});
}

sub is_login_available {
    my ($login, $id) = @_;
    $login // '' ne '' or return;
    my $dups = $dbh->selectcol_arrayref(q~
        SELECT id FROM accounts WHERE login = ?~,
        undef, $login) or return 1;
    # Several logins, or a single login with different id => error.
    @$dups > 1 || @$dups == 1 && (!$id || $id != $dups->[0]) ? 0 : 1;
}

sub validate_login {
    my ($self, $id) = @_;
    is_login_available($self->{login}, $id) || msg(1103);
}

# p: save_settings, is_ooc, is_hidden, commit.
sub insert {
    my ($self, $contest_id, %p) = @_;
    my $training_contests = $dbh->selectall_arrayref(q~
        SELECT id, closed FROM contests WHERE ctype = 1 AND closed = 0~, { Slice => {} });
    @$training_contests or return msg(1092);

    my $aid = new_id;
    my $new_settings = $p{save_settings} ? CATS::Settings::as_storable : '';
    $dbh->do(q~
        INSERT INTO accounts (
            id, srole, passwd, settings, ~ . join (', ', param_names()) . q~
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)~, {},
        $aid, $CATS::Privileges::srole_user, $self->{password1}, $new_settings, $self->values
    );
    $self->{id} = $aid;
    add_to_contest(contest_id => $_->{id}, account_id => $aid, is_ooc => 1)
        for @$training_contests;
    if ($contest_id && !grep $_->{id} == $contest_id, @$training_contests) {
        add_to_contest(contest_id => $contest_id, account_id => $aid,
            is_ooc => $p{is_ooc} // 1, is_hidden => $p{is_hidden} // 0);
    }

    $dbh->commit if $p{commit} // 1;
    1;
}

sub prepare_password {
    my ($u, $set_password) = @_;
    if ($set_password) {
        $u->{passwd} = hash_password($u->{password1});
        msg(1085, $u->{team_name});
    }
    delete @$u{qw(password1 password2)};
}

sub update_settings_item {
    my ($h, $item, $v) = @_;
    $h or die;

    my @path = split /\./, $item->{name};
    my $k = pop @path;
    $h = $h->{$_} //= {} for @path;

    $v = 1 if $v && $v eq 'on';
    defined $v && $v ne '' && (!defined($item->{default}) || $v != $item->{default}) ?
        $h->{$k} = $v : delete $h->{$k};
}

my $html_units = join '|', qw(cm mm in px pt pc em ex ch rem vw vmin vmax %);

my @editable_settings = (
    { name => 'hide_envelopes', default => 0 },
    { name => 'display_input', default => 0 },
    {
        name => 'console.autoupdate', default => 30,
        validate => sub { $_[0] eq '' || $_[0] =~ /^\d+$/ && $_[0] >= 20 ? 1 : msg(1046, res_str(809), 20) }
    },
    {
        name => 'source_width', default => 90,
        validate => sub { $_[0] eq '' || $_[0] =~ /^\d+$/ && $_[0] <= 200 ? 1 : msg(1045, res_str(810), 0, 200) }
    },
    {
        name => 'listview.row_height', default => '',
        validate => sub { $_[0] eq '' || $_[0] =~ /^\d+(?:$html_units)?$/ ? 1 : msg(1246, '') }
    },
);

sub setting_names { map "settings.$_->{name}", @editable_settings }

sub update_settings {
    my ($p, $settings_root) = @_;
    for (@editable_settings) {
        return if $_->{validate} && !$_->{validate}->($p->{"settings.$_->{name}"} // '');
    }
    for (@editable_settings) {
        update_settings_item($settings_root, $_, $p->{"settings.$_->{name}"});
    }
    1;
}

# Admin adds new user to current contest
sub new_save {
    my ($p) = @_;
    $is_jury or return;
    my $u = CATS::User->new->parse_params($p);
    $u->validate_params(validate_password => 1) or return;
    $u->{password1} = hash_password($u->{password1});
    $u->insert($cid) or return;
}

sub edit_save {
    my ($p) = @_;
    my $u = CATS::User->new->parse_params($p);
    if (!$is_root) {
        delete $u->{restrict_ips};
    }
    # Simple $is_jury check is insufficient since jury member
    # can add any team to his contest.
    my $set_password = $p->{set_password} && $is_root;
    my $id = $p->{id};
    my $old_user = $id ? CATS::User->new->load($id, [ qw(settings srole) ]) : undef;
    # Only admins may edit other admins.
    return if !$is_root && CATS::Privileges::unpack_privs($old_user->{srole})->{is_root};

    $u->validate_params(
        validate_password => $set_password, id => $id,
        # Need at least $is_jury in all official contests where $u participated.
        allow_official_rename => $is_root)
        or return;
    $old_user->{settings} ||= {};
    update_settings($p, $old_user->{settings}) or return;
    prepare_password($u, $set_password);

    $u->{locked} = $p->{locked} ? 1 : 0 if $is_root;

    my $new_settings = Storable::nfreeze($old_user->{settings});
    $u->{settings} = $new_settings if $new_settings ne ($old_user->{frozen_settings} // '');

    $dbh->do(_u $sql->update('accounts', { %$u }, { id => $id }));
    $dbh->commit;
    msg(1059, $u->{team_name});
}

sub profile_save {
    my ($p) = @_;
    my $u = CATS::User->new->parse_params($p);
    if (!$is_root) {
        delete $u->{restrict_ips};
    }

    $u->validate_params(validate_password => $p->{set_password}, id => $uid) or return;
    update_settings($p, $settings) or return;
    prepare_password($u, $p->{set_password});
    $dbh->do(_u $sql->update('accounts', { %$u }, { id => $uid }));
    $dbh->commit;
}

sub trim { s/^\s+|\s+$//; $_; }

# (Mass-)register users by jury.
sub register_by_login {
    my ($login, $contest_id, $make_jury) = @_;
    $is_jury or return;
    my @logins = map trim, split(/,/, $login || '') or return msg(1101);
    my %aids;
    for (@logins) {
        length $_ <= 50 or return msg(1101);
        my ($aid) = $dbh->selectrow_array(q~
            SELECT id FROM accounts WHERE login = ?~, undef, $_);
        $aid or return msg(1118, $_);
        !get_registered_contestant(contest_id => $contest_id, account_id => $aid)
            or return msg(1120, $_);
        $aids{$aid} = 1;
    }
    %aids or return msg(1118);
    my %jury_flags = $make_jury ? (is_jury => 1, is_hidden => 1) : ();
    add_to_contest(contest_id => $contest_id, account_id => $_, is_remote => 1, is_ooc => 1, %jury_flags)
        for keys %aids;
    $dbh->commit;
    msg($make_jury ? 1125 : 1119, join ',', @logins);
    [ keys %aids ];
}


sub make_sid {
    my @ch = ('A'..'Z', 'a'..'z', '0'..'9');
    join '', map { $ch[rand @ch] } 1..30;
}

sub make_token {
    my ($user_id) = @_;
    my $token = CATS::User::make_sid;
    $dbh->do(_u $sql->insert('account_tokens',
        { token => $token, account_id => $user_id, usages_left => 1 }))
        or return;
    $dbh->commit;
    $token;
}

sub _prepare_msg_inserts {
    return map $dbh->prepare($_), (
    q~
        INSERT INTO messages (id, text, received, broadcast, contest_id, problem_id)
        VALUES (?, ?, 0, ?, ?, ?)~,
    q~
        INSERT INTO events (id, ts, account_id) VALUES (?, CURRENT_TIMESTAMP, ?)~);
}

# Params: user_set, message, contest_id, problem_id.
sub send_message {
    my %p = @_;
    $p{message} ne '' or return 0;
    my $get_aid_sth = $dbh->prepare(q~
        SELECT account_id FROM contest_accounts WHERE id = ?~);
    my ($insert_msg_sth, $insert_ev_sth) = _prepare_msg_inserts;
    my $count = 0;
    for (@{$p{user_set}}) {
        $get_aid_sth->execute($_);
        my ($aid) = $get_aid_sth->fetchrow_array;
        $get_aid_sth->finish;
        $aid or next;
        my $msg_id = new_id;
        $insert_msg_sth->execute($msg_id, $p{message}, 0, $p{contest_id}, $p{problem_id});
        $insert_ev_sth->execute($msg_id, $aid);
        ++$count;
    }
    $count;
}

# Params: message, contest_id, problem_id.
sub send_broadcast {
    my %p = @_;
    $p{message} ne '' or return;
    my ($insert_msg_sth, $insert_ev_sth) = _prepare_msg_inserts;
    my $msg_id = new_id;
    $insert_msg_sth->execute($msg_id, $p{message}, 1, $p{contest_id}, $p{problem_id});
    $insert_ev_sth->execute($msg_id, undef);
}

# Params: user_set, tag.
sub set_tag {
    my %p = @_;
    my $s = $dbh->prepare(q~
        UPDATE contest_accounts SET tag = ? WHERE id = ?~);
    my $set_count = 0;
    for my $user_id (@{$p{user_set}}) {
        $s->bind_param(1, $p{tag});
        $s->bind_param(2, $user_id);
        $set_count += $s->execute;
    }
    $s->finish;
    $dbh->commit;
    msg(1019, $set_count);
}

# Params: user_set, site_id.
sub set_site {
    my %p = @_;
    my ($cond, @param);
    if ($is_jury || !$user->{site_id}) {
        $cond = 'site_id IS DISTINCT FROM ?';
        @param = ($p{site_id});
    }
    elsif ($p{site_id}) {
        $cond = 'site_id IS NULL';
    }
    else {
        $cond = 'site_id = ?';
        @param = ($user->{site_id}); # Site org can only assign to his own site.
    }

    my $s = $dbh->prepare(qq~
        UPDATE contest_accounts SET site_id = ?
        WHERE id = ? AND contest_id = ? AND $cond~);
    my $count = 0;
    for (@{$p{user_set}}) {
        # Only jury can modify his own site.
        $is_jury || $_ != $user->{ca_id} or next;
        $count += $s->execute($p{site_id}, $_, $cid, @param);
    }
    $s->finish;
    if ($count) {
        $dbh->commit;
        CATS::RankTable::Cache::remove($cid);
    }
    msg(1024, $count);
}

my @password_chars = ('a'..'z', 'A'..'Z', '0'..'9', '_');

# Params: user_set, len.
sub gen_passwords {
    my %p = @_;
    $is_jury or return;
    $p{len} && $p{len} <= 30 or return;
    my $get_login_sth = $dbh->prepare(q~
        SELECT A.id, A.login, CA.is_jury FROM accounts A
        INNER JOIN contest_accounts CA ON CA.account_id = A.id
        WHERE CA.id = ? AND CA.contest_id = ?~);
    my $set_password_sth = $dbh->prepare(q~
        UPDATE accounts SET passwd = ? WHERE id = ?~);
    my @res;
    for (@{$p{user_set}}) {
        $get_login_sth->execute($_, $cid);
        my ($id, $login, $user_is_jury) = $get_login_sth->fetchrow_array;
        $get_login_sth->finish;
        $id && $login && !$user_is_jury or next;
        my $password = join '', map $password_chars[rand(@password_chars)], 1..$p{len};
        $set_password_sth->execute(hash_password($password), $id);
        push @res, [ $id, $login, $password ];
    }
    $dbh->commit if @res;
    $t->param(new_passwords => \@res);
}

sub _save_attributes_single {
    my ($p, $user_id, $attr_names) = @_;

    my (%set, %where);
    for (@$attr_names) {
        my $v = $set{"is_$_"} = $p->web_param($_ . $user_id) ? 1 : 0;
        # Only perform update if it actually changes values.
        $where{"is_$_"} = { '!=', $v };
    }
    # Security: Forbid changing of user parameters in other contests.
    my ($s, @b) = $sql->update('contest_accounts',
        \%set, { id => $user_id, contest_id => $cid, -or => \%where }
    );
    $dbh->do(_u $sql->update('contest_accounts',
        \%set, { id => $user_id, contest_id => $cid, -or => \%where }
    ));
}

sub save_attributes_finalize {
    my ($changed_count) = @_;
    if ($changed_count) {
        $dbh->commit;
        CATS::RankTable::Cache::remove($cid);
    }
    msg(1018, $changed_count);
}

sub save_attributes_jury {
    my ($p) = @_;
    my $changed_count = 0;
    for my $user_id (@{$p->{user_set}}) {
        # Forbid removing is_jury privilege from an admin.
        my ($srole) = $dbh->selectrow_array(q~
            SELECT A.srole FROM accounts A
            INNER JOIN contest_accounts CA ON A.id = CA.account_id
            WHERE CA.id = ?~, undef,
            $user_id
        );
        $changed_count += _save_attributes_single(
            $p, $user_id, [
            (CATS::Privileges::is_root($srole) || !$user->privs->{grant_jury} ? () : 'jury'),
            qw(hidden remote ooc site_org) ]);
    }
    save_attributes_finalize($changed_count);
}

sub save_attributes_org {
    my ($p) = @_;
    my $changed_count = 0;
    for my $user_id (@{$p->{user_set}}) {
        if (!$is_jury) {
            my ($aid, $site_id) = $dbh->selectrow_array(q~
                SELECT account_id, site_id FROM contest_accounts CA
                WHERE CA.id = ?~, undef,
                $user_id
            );
            (!$user->{site_id} || $user->{site_id} == $site_id) && $aid != $uid or next;
        }
        $changed_count += _save_attributes_single($p, $user_id, [ qw(remote ooc) ]);
    }
    save_attributes_finalize($changed_count);
}

sub _add_multiple {
    my ($source_users, $sites) = @_;
    my $dest_sth = $dbh->prepare(q~
        SELECT 1 FROM contest_accounts WHERE contest_id = ? AND account_id = ?~);
    my ($count, $already) = (0, 0);
    for (@$source_users) {
        $dest_sth->execute($cid, $_->{account_id});
        if ($dest_sth->fetch) {
            $already++;
        }
        else {
            $_->{site_id} && $sites->{$_->{site_id}} or $_->{site_id} = undef;
            add_to_contest(%$_, contest_id => $cid);
            $count++;
        }
        $dest_sth->finish;
    }
    $dbh->commit if $count;
    msg(1096, $count);
    msg(1097, $already) if $already;
}

sub copy_from_contest {
    my ($source_cid, $include_ooc) = @_;
    $source_cid && $source_cid != $cid && $is_jury or return;
    is_jury_in_contest(contest_id => $source_cid) or return;
    my $sites = $dbh->selectall_hashref(q~
        SELECT site_id FROM contest_sites WHERE contest_id = ?~, 'site_id', undef,
        $cid);
    my $ooc_cond = $include_ooc ? '' : ' AND is_ooc = 0';
    my $source_users = $dbh->selectall_arrayref(qq~
        SELECT account_id, site_id, is_ooc, is_remote, is_site_org
        FROM contest_accounts
        WHERE is_jury = 0 AND is_hidden = 0 AND is_virtual = 0$ooc_cond AND
            contest_id = ?~, { Slice => {} },
        $source_cid);
    _add_multiple($source_users, $sites);
}

sub copy_from_acc_group {
    my ($source_group_id, $include_hidden, $include_admins) = @_;
    $source_group_id && $is_jury or return;
    my $hidden_cond = $include_hidden ? '' : ' AND is_hidden = 0';
    my $admin_cond = $include_admins ? '' : ' AND is_admin = 0';
    my $source_users = $dbh->selectall_arrayref(qq~
        SELECT account_id FROM acc_group_accounts
        WHERE acc_group_id = ?$hidden_cond$admin_cond~, { Slice => {} },
        $source_group_id);
    _add_multiple($source_users, {});
}

sub _url_f_selected {
    my ($f, @rest) = @_;
    (href => url_f($f, @rest), selected => $f);
}

sub submenu {
    my ($selected, $user_id, $site_id) = @_;
    $site_id //= 0;
    my $is_profile = $uid && $uid == $user_id;
    my @m = (
        (($is_root || $is_profile) && $selected eq 'user_contacts' ? (
            { href => url_f('user_contacts_edit', uid => $user_id), item => res_str(587), selected => '', new => 1 }
        ) : ()),
        (($is_root || $is_profile) && $selected eq 'user_relations' ? (
            { href => url_f('user_relations_edit', uid => $user_id), item => res_str(598), selected => '', new => 1 }
        ) : ()),
        (
            $is_jury ?
                ({ href => url_f('users_edit', uid => $user_id), item => res_str(573), selected => 'edit' }) :
            $is_profile ?
                ({ _url_f_selected('profile'), item => res_str(518) }) :
                ()
        ),
        { _url_f_selected('user_stats', uid => $user_id), item => res_str(574) },
        (!$is_root ? () : (
            { _url_f_selected('user_settings', uid => $user_id), item => res_str(575) },
        )),
        { _url_f_selected('user_contacts', uid => $user_id), item => res_str(586) },
        ($is_root || $is_profile ?
            ({ _url_f_selected('user_relations', uid => $user_id), item => res_str(597) }) : ()),
        ($is_jury || $user->{is_site_org} && (!$user->{site_id} || $user->{site_id} == $site_id) ? (
            { _url_f_selected('user_vdiff', uid => $user_id), item => res_str(580) },
            { _url_f_selected('user_ip', uid => $user_id), item => res_str(576) },
            { href => url_f('users', search(id => $user_id)), item => res_str(599), selected => '' },
        ) : ()),
    );
    $_->{selected} = $_->{selected} eq $selected for @m;
    (submenu => \@m);
}

sub users_submenu {
    my ($p, $selected) = @_;
    $selected //= $p->{f} if $p;
    my @m = (
        ($is_jury ? (
            { href => url_f('users_new'), item => res_str(541), new => 1 },
            { _url_f_selected('users_import'), item => res_str(564) },
            { _url_f_selected('users_add_participants'), item => res_str(584) },
            ($is_root ?
                { _url_f_selected('users_all_settings'), item => res_str(575) } : ()),
            { _url_f_selected('users_snippets'), item => res_str(698) },
        ) : ()),
        ($user->{is_site_org} ? (
            ($user->{site_id} ?
                { href => url_f('users', search => 'site_id=my'), item => res_str(582) } : ()),
            { href => url_f('users', search => 'site_id=0'), item => res_str(583) },
        ) : ()),
        { href => url_f('acc_groups', $is_root ? (search => 'in_contest(this)') : ()),
            item => res_str(410) },
    );
    $_->{selected} = $_->{selected} && $_->{selected} eq $selected for @m;
    (submenu => \@m);
}

sub logins_maybe_added {
    my ($p, $url_p, $account_ids) = @_;
    @$account_ids ?
        (href_view_added => url_f(@$url_p, search => join ',', map "id=$_", @$account_ids)) :
        (logins_to_add => $p->{logins_to_add});
}

sub ca_ids_to_accounts {
    my ($accounts) = @_;
    $dbh->selectcol_arrayref(_u $sql->select(
        'contest_accounts', 'account_id', { contest_id => $cid, id => $accounts }));
}

1;
