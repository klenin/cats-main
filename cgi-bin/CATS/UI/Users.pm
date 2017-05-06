package CATS::UI::Users;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use Storable qw(freeze thaw);

use CATS::Constants;
use CATS::Countries;
use CATS::DB;
use CATS::IP;
use CATS::ListView;
use CATS::Misc qw(
    $t $is_jury $is_root $is_team $sid $cid $uid $contest $is_virtual $settings
    format_diff_time init_template msg res_str url_f auto_ext);
use CATS::RankTable;
use CATS::User;
use CATS::Utils qw(url_function date_to_iso);
use CATS::Web qw(param param_on redirect url_param);

my $hash_password;
BEGIN {
    $hash_password = eval { require Authen::Passphrase::BlowfishCrypt; } ?
        sub {
            Authen::Passphrase::BlowfishCrypt->new(
                cost => 8, salt_random => 1, passphrase => $_[0])->as_rfc2307;
        } :
        sub { $_[0] }
}

# Admin adds new user to current contest
sub users_new_save
{
    $is_jury or return;
    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->{password1} = $hash_password->($u->{password1});
    $u->insert($cid) or return;
}

sub user_submenu
{
    my ($selected, $user_id) = @_;
    my @m = (
        ($is_jury ?
            ({ href => url_f('users', edit => $user_id), item => res_str(573), selected => 'edit' }) :
            ({ href => url_f('profile'), item => res_str(518), selected => 'profile' })
        ),
        { href => url_f('user_stats', uid => $user_id), item => res_str(574), selected => 'user_stats' },
        (!$is_root ? () : (
            { href => url_f('user_settings', uid => $user_id), item => res_str(575), selected => 'user_settings' },
            { href => url_f('user_ip', uid => $user_id), item => res_str(576), selected => 'user_ip' },
        )),
        (!$is_jury ? () : (
            { href => url_f('user_vdiff', uid => $user_id), item => res_str(580), selected => 'user_vdiff' },
        )),
    );
    $_->{selected} = $_->{selected} eq $selected for @m;
    (submenu => \@m);
}

sub users_edit_frame
{
    init_template('users_edit.html.tt');

    my $id = url_param('edit') or return;
    my $u = CATS::User->new->load($id, [ qw(locked settings srole) ]) or return;
    $t->param(
        user_submenu('edit', $id),
        title_suffix => $u->{team_name},
        %$u, privs => CATS::Misc::unpack_privs($u->{srole}),
        is_root => $is_root,
        id => $id,
        countries => \@CATS::Countries::countries,
        href_action => url_f('users'),
        href_impersonate => url_f('users', impersonate => $id));
}

sub prepare_password {
    my ($u, $set_password) = @_;
    if ($set_password) {
        $u->{passwd} = $hash_password->($u->{password1});
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

my @editable_settings = (
    { name => 'hide_envelopes', default => 0 },
    { name => 'display_input', default => 0 },
    {
        name => 'console.autoupdate', default => 30,
        validate => sub { $_[0] eq '' || $_[0] =~ /^\d+$/ && $_[0] >= 20 ? 1 : msg(1046, res_str(809), 20) }
    },
);

sub update_settings {
    my ($settings_root) = @_;
    for (@editable_settings) {
        return if $_->{validate} && !$_->{validate}->(param("settings.$_->{name}"));
    }
    for (@editable_settings) {
        update_settings_item($settings_root, $_, param("settings.$_->{name}"));
    }
    1;
}

sub users_edit_save
{
    my $u = CATS::User->new->parse_params;
    # Simple $is_jury check is insufficient since jury member
    # can add any team to his contest.
    my $set_password = param_on('set_password') && $is_root;
    my $id = param('id');
    my $old_user = $id ? CATS::User->new->load($id, [ qw(settings) ]) : undef;

    $u->validate_params(
        validate_password => $set_password, id => $id,
        # Need at least $is_jury in all official contests where $u participated.
        allow_official_rename => $is_root)
        or return;
    $old_user->{settings} ||= {};
    update_settings($old_user->{settings}) or return;
    prepare_password($u, $set_password);

    $u->{locked} = param('locked') ? 1 : 0 if $is_root;

    my $new_settings = freeze($old_user->{settings});
    $u->{settings} = $new_settings if $new_settings ne ($old_user->{frozen_settings} // '');

    $dbh->do(_u $sql->update('accounts', { %$u }, { id => $id }));
    $dbh->commit;
}

sub users_import_frame
{
    init_template('users_import.html.tt');
    $is_root or return;
    $t->param(href_action => url_f('users_import'));
    param('do') or return;
    my $do_import = param('do_import');
    my @report;
    for my $line (split "\r\n", Encode::decode_utf8(param('user_list'))) {
        my $u = CATS::User->new;
        @$u{qw(team_name login password1 city)} = split "\t", $line;
        my $r = eval {
            $u->{password1} = $hash_password->($u->{password1});
            $u->insert($contest->{id}, is_ooc => 0, commit => 0); 'ok'
        } || $@;
        push @report, $u->{team_name} . "-- $r";
    }
    $do_import ? $dbh->commit : $dbh->rollback;
    push @report, ($do_import ? 'Import' : 'Test') . ' complete';
    $t->param(report => join "\n", @report);
}

sub registration_frame
{
    init_template('registration.html.tt');

    $t->param(countries => \@CATS::Countries::countries, href_login => url_f('login'));

    defined param('register')
        or return;

    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->{password1} = $hash_password->($u->{password1});
    $u->insert(undef, save_settings => 1) or return;
    $t->param(successfully_registred => 1);
}

sub profile_save
{
    my $u = CATS::User->new->parse_params;
    my $set_password = param_on('set_password');

    $u->validate_params(validate_password => $set_password, id => $uid) or return;
    update_settings($settings) or return;
    prepare_password($u, $set_password);
    $dbh->do(_u $sql->update('accounts', { %$u }, { id => $uid }));
    $dbh->commit;
}

sub apply_rec
{
    my ($val, $sub) = @_;
    ref $val eq 'HASH' ?
        { map { $_ => apply_rec($val->{$_}, $sub) } keys %$val } :
        $sub->($val);
}

sub display_settings
{
    my ($s) = @_;
    $t->param(settings => $s);
    $is_root or return;
    # Data::Dumper escapes UTF-8 characters into \x{...} sequences.
    # Work around by dumping encoded strings, then decoding the result.
    my $d = Data::Dumper->new([ apply_rec($s, \&Encode::encode_utf8) ]);
    $d->Quotekeys(0);
    $d->Sortkeys(1);
    $t->param(settings_dump => Encode::decode_utf8($d->Dump));
}

sub profile_frame
{
    my ($p) = @_;
    init_template(auto_ext('user_profile', $p->{json}));
    $uid or return;
    if (defined $p->{clear} && $is_team) {
        $settings = {};
        msg(1029, $CATS::Misc::team_name);
    }
    profile_save if defined $p->{edit_save} && $is_team;

    my $u = CATS::User->new->load($uid) or return;
    my ($is_some_jury) = $is_jury || $dbh->selectrow_array(q~
        SELECT CA.contest_id FROM contest_accounts CA WHERE CA.account_id = ? AND CA.is_jury = 1~, undef,
        $uid);
    $t->param(
        user_submenu('profile', $uid),
        countries => \@CATS::Countries::countries,
        href_action => url_f('users'),
        title_suffix => res_str(518),
        profile_langs => [ map { href => url_f('profile', lang => $_), name => $_ }, @cats::langs ],
        is_root => $is_root,
        is_some_jury => $is_some_jury,
        %$u);
    display_settings($settings);
}

sub users_send_message
{
    my %p = @_;
    $p{'message'} ne '' or return;
    my $s = $dbh->prepare(qq~
        INSERT INTO messages (id, send_time, text, account_id, received)
            VALUES (?, CURRENT_TIMESTAMP, ?, ?, 0)~
    );
    my $count = 0;
    for (split ':', $p{'user_set'})
    {
        next unless param_on("msg$_");
        ++$count;
        $s->bind_param(1, new_id);
        $s->bind_param(2, $p{'message'}, { ora_type => 113 });
        $s->bind_param(3, $_);
        $s->execute;
    }
    $s->finish;
    $count;
}

sub users_set_tag
{
    my %p = @_;
    my $s = $dbh->prepare(q~
        UPDATE contest_accounts SET tag = ? WHERE id = ?~);
    my $set_count = 0;
    for my $user_id (split ':', $p{user_set}) {
        param_on("msg$user_id") or next;
        $s->bind_param(1, $p{tag}, { ora_type => 113 });
        $s->bind_param(2, $user_id);
        $set_count += $s->execute;
    }
    $s->finish;
    $dbh->commit;
    msg(1019, $set_count);
}

sub users_send_broadcast
{
    my %p = @_;
    $p{'message'} ne '' or return;
    my $s = $dbh->prepare(qq~
        INSERT INTO messages (id, send_time, text, account_id, broadcast)
            VALUES(?, CURRENT_TIMESTAMP, ?, NULL, 1)~
    );
    $s->bind_param(1, new_id);
    $s->bind_param(2, $p{'message'}, { ora_type => 113 });
    $s->execute;
    $s->finish;
}

sub users_delete
{
    my $caid = url_param('delete');
    my ($aid, $srole, $name) = $dbh->selectrow_array(q~
        SELECT A.id, A.srole, A.team_name FROM accounts A
            INNER JOIN contest_accounts CA ON A.id = CA.account_id
            WHERE CA.id = ?~, undef,
        $caid);
    $aid or return;
    $name = Encode::decode_utf8($name);
    $srole != $cats::srole_root or return msg(1095, $name);

    $dbh->do(q~
        DELETE FROM contest_accounts WHERE id = ?~, undef,
        $caid);
    my $contests_left = $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM contest_accounts WHERE account_id=?~, undef,
        $aid);
    if ($contests_left) {
        msg(1093, $name, $contests_left)
    }
    else {
        $dbh->do(q~
            DELETE FROM accounts WHERE id = ?~, undef,
            $aid);
        msg(1094, $name);
    }
    $dbh->commit;
}

sub users_save_attributes
{
    my $changed_count = 0;
    for my $user_id (split(':', param('user_set'))) {
        my $jury = param_on("jury$user_id");
        my $ooc = param_on("ooc$user_id");
        my $remote = param_on("remote$user_id");
        my $hidden = param_on("hidden$user_id");

        # Forbid removing is_jury privilege from an admin.
        my ($srole) = $dbh->selectrow_array(q~
            SELECT A.srole FROM accounts A
                INNER JOIN contest_accounts CA ON A.id = CA.account_id
                WHERE CA.id = ?~, undef,
            $user_id
        );
        $jury = 1 if $srole == $cats::srole_root;

        # Security: Forbid changing of user parameters in other contests.
        my $changed = $dbh->do(q~
            UPDATE contest_accounts
                SET is_jury = ?, is_hidden = ?, is_remote = ?, is_ooc = ?
                WHERE id = ? AND contest_id = ? AND
                    (is_jury <> ? OR is_hidden <> ? OR is_remote <> ? OR is_ooc <> ?)~, undef,
            $jury, $hidden, $remote, $ooc,
            $user_id, $cid,
            $jury, $hidden, $remote, $ooc,
        );
        $changed_count += $changed;
    }
    if ($changed_count) {
        $dbh->commit;
        CATS::RankTable::remove_cache($cid);
    }
    msg(1018, $changed_count);

}

sub users_impersonate
{
    my $new_user_id = param('impersonate') or return;
    my $new_sid = CATS::User::make_sid;
    $dbh->selectrow_array(q~
        SELECT 1 FROM accounts WHERE id = ?~, undef, $new_user_id) or return;
    $dbh->do(q~
        UPDATE accounts SET last_ip = ?, sid = ? WHERE id = ?~, undef,
        CATS::IP::get_ip, $new_sid, $new_user_id);
    $dbh->commit;
    redirect(url_function('contests', sid => $new_sid, cid => $cid));
}

sub users_frame
{
    if ($is_jury) {
        return CATS::User::new_frame if defined url_param('new');
        return users_edit_frame if defined url_param('edit');
    }
    return users_impersonate if defined url_param('impersonate') && $is_root;

    my $lv = CATS::ListView->new(
        name => 'users' . ($contest->is_practice ? '_practice' : ''),
        array_name => 'users',
        template => auto_ext('users'));
    $t->param(messages => $is_jury, title_suffix => res_str(526));

    if ($is_jury) {
        users_delete if defined url_param('delete');
        users_new_save if defined param('new_save');
        users_edit_save if defined param('edit_save');

        users_save_attributes if defined param('save_attributes');
        users_set_tag(user_set => param('user_set'), tag => param('tag_to_set'))
            if defined param('set_tag');
        CATS::User::register_by_login(param('login_to_register'), $cid)
            if defined param('register_new');

        if (defined param('send_message'))
        {
            if (param_on('send_message_all'))
            {
                users_send_broadcast(message => param('message_text'));
                msg(1058);
            }
            else
            {
                my $count = users_send_message(
                    user_set => param('user_set'), message => param('message_text'));
                msg(1057, $count);
            }
            $dbh->commit;
        }
    }

    my @cols;
    if ($is_jury)
    {
        @cols = ( { caption => res_str(616), order_by => 'login', width => '25%' } );
    }

    push @cols,
        { caption => res_str(608), order_by => 'team_name', width => '40%' },
        { caption => res_str(629), order_by => 'tag', width => '5%' };

    if ($is_jury)
    {
        push @cols, (
            { caption => res_str(611), order_by => 'is_jury', width => '5%' },
            { caption => res_str(612), order_by => 'is_ooc', width => '5%' },
            { caption => res_str(613), order_by => 'is_remote', width => '5%' },
            { caption => res_str(614), order_by => 'is_hidden', width => '5%' },
        );
    }

    push @cols, (
        { caption => res_str(607), order_by => 'country', width => '5%' },
        { caption => res_str(609), order_by => 'rating', width => '5%' },
        { caption => res_str(622), order_by => 'is_virtual', width => '5%' },
    );

    $lv->define_columns(url_f('users'), $is_jury ? 3 : 2, 1, \@cols);

    return if !$is_jury && param('json') && $contest->is_practice;

    my @fields = qw(
        A.id A.country A.motto A.login A.team_name A.city
        CA.is_jury CA.is_ooc CA.is_remote CA.is_hidden CA.is_virtual CA.diff_time CA.tag);
    $lv->define_db_searches(\@fields);
    $lv->define_db_searches({ 'CA.id' => 'CA.id' });

    my $fields = join ', ', @fields;
    my $sql = sprintf qq~
        SELECT CA.id, $fields, COUNT(DISTINCT R.problem_id) as rating
        FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id
            INNER JOIN contests C ON CA.contest_id = C.id
            LEFT JOIN reqs R ON
                R.state = $cats::st_accepted AND R.account_id = A.id AND R.contest_id = C.id%s
        WHERE C.id = ?%s %s GROUP BY CA.id, $fields ~ . $lv->order_by,
        ($is_jury ? ('', '') : (
            ' AND (R.submit_time < C.freeze_date OR C.defreeze_date < CURRENT_TIMESTAMP)',
            ' AND CA.is_hidden = 0')),
        $lv->maybe_where_cond;

    my $c = $dbh->prepare($sql);
    $c->execute($cid, $lv->where_params);

    my $fetch_record = sub($)
    {
        my (
            $caid, $aid, $country_abbr, $motto, $login, $team_name, $city, $jury,
            $ooc, $remote, $hidden, $virtual, $virtual_diff_time, $tag, $accepted
        ) = $_[0]->fetchrow_array
            or return ();
        my ($country, $flag) = CATS::Countries::get_flag($country_abbr);
        return (
            href_delete => url_f('users', delete => $caid),
            href_edit => url_f('users', edit => $aid),
            href_stats => url_f('user_stats', uid => $aid),
            motto => $motto,
            id => $caid,
            account_id => $aid,
            login => $login,
            team_name => $team_name,
            city => $city,
            tag => $tag,
            country => $country,
            flag => $flag,
            accepted => $accepted,
            jury => $jury,
            hidden => $hidden,
            ooc => $ooc,
            remote => $remote,
            virtual => $virtual,
            virtual_diff_time => $virtual_diff_time,
            virtual_diff_time_minutes => int(($virtual_diff_time // 0) * 24 * 60 | 0.5),
            virtual_diff_time_fmt => format_diff_time($virtual_diff_time, 1),
         );
    };

    $lv->attach(url_f('users'), $fetch_record, $c);

    if ($is_jury)
    {
        $t->param(
            submenu => [
                { href => url_f('users', new => 1), item => res_str(541) },
                { href => url_f('users_import'), item => res_str(564) },
            ],
            editable => 1
        );
    }

    $c->finish;
}

sub user_stats_frame
{
    init_template('user_stats.html.tt');
    my $uid = param('uid') or return;
    my $envelopes_sql = $is_root ?
        ', (SELECT COUNT(*) FROM reqs R WHERE R.account_id = A.id AND R.received = 0) AS envelopes' : '';
    my $u = $dbh->selectrow_hashref(qq~
        SELECT A.*, last_login AS last_login_date$envelopes_sql
        FROM accounts A WHERE A.id = ?~, { Slice => {} },
        $uid) or return;
    my $hidden_cond = $is_root ? '' :
        'AND C.is_hidden = 0 AND (CA.is_hidden = 0 OR CA.is_hidden IS NULL) AND C.defreeze_date < CURRENT_TIMESTAMP';
    my $contests = $dbh->selectall_arrayref(qq~
        SELECT C.id, C.title, CA.id AS caid, CA.is_jury, C.start_date + CA.diff_time AS start_date,
            (SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
                WHERE R.contest_id = C.id AND R.account_id = CA.account_id AND R.state = $cats::st_accepted
            ) AS accepted_count,
            (SELECT COUNT(*) FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.status < $cats::problem_st_hidden
            ) AS problem_count
        FROM contests C INNER JOIN contest_accounts CA ON CA.contest_id = C.id
        WHERE
            CA.account_id = ? AND C.ctype = 0 $hidden_cond
        ORDER BY C.start_date + CA.diff_time DESC~,
        { Slice => {} }, $uid);
    my $pr = sub { url_f(
        'console', uf => $uid, i_value => -1, se => 'user_stats', show_results => 1, search => $_[0], rows => 30
    ) };
    for (@$contests) {
        $_->{href_send_message} = url_f('send_message_box', caid => $_->{caid}) if $is_root;
        $_->{href_problems} = url_function('problems', sid => $sid, cid => $_->{id});
        $_->{href_submits} = url_function('console', sid => $sid, cid => $_->{id},
            uf => $uid, i_value => -1, se => 'user_stats', show_results => 1, rows => 30, search => "contest_id=$_->{id}");
    }
    $t->param(
        user_submenu('user_stats', $uid),
        %$u, contests => $contests, is_root => $is_root,
        CATS::IP::linkify_ip($u->{last_ip}),
        ($is_jury ? (href_edit => url_f('users', edit => $uid)) : ()),
        href_all_problems => $pr->(''),
        href_solved_problems => $pr->('state=OK'),
        title_suffix => $u->{team_name},
    );
}

sub user_settings_frame
{
    init_template('user_settings.html.tt');
    $is_root or return;
    my $user_id = param('uid') or return;

    my $cleared;
    if (param('clear')) {
        $cleared = $dbh->do(q~
            UPDATE accounts SET settings = NULL WHERE id = ?~, undef,
            $user_id
        ) && $dbh->commit;
    }

    my ($team_name, $user_settings) = $dbh->selectrow_array(q~
        SELECT team_name, settings FROM accounts WHERE id = ?~, undef,
        $user_id);

    msg(1029, $team_name) if $cleared;
    display_settings(thaw($user_settings)) if $user_settings;
    $t->param(
        user_submenu('user_settings', $user_id),
        team_name => $team_name,
        title_suffix => $team_name,
    );
}

sub user_ip_frame
{
    my ($p) = @_;
    $is_root or return;
    init_template('user_ip.html.tt');
    my $uid = $p->{uid} or return;
    my $u = $dbh->selectrow_hashref(q~
        SELECT A.* FROM accounts A WHERE A.id = ?~, { Slice => {} },
        $uid) or return;
    my $events = $dbh->selectall_arrayref(q~
        SELECT MAX(E.ts) AS ts, E.ip FROM events E WHERE E.account_id = ?
        GROUP BY E.ip ORDER BY 1 DESC~,
        { Slice => {} }, $uid);
    unshift @$events, { ts => $u->{last_login}, ip => $u->{last_ip } };
    for my $e (@$events) {
        my %linkified = CATS::IP::linkify_ip($e->{ip});
        $e->{$_} = $linkified{$_} for keys %linkified;
    }
    $t->param(
        user_submenu('user_ip', $uid),
        %$u,
        events => $events,
        title_suffix => $u->{team_name},
    );
}

my $vdiff_units = { min => 1 / 24 / 60, hour => 1 / 24, day => 1, week => 7 };

sub user_vdiff_save
{
    my ($p, $u) = @_;
    $p->{save} or return;
    my $k = $vdiff_units->{$p->{units} // ''} or return;
    $u->{diff_time} = $p->{diff_time} ? $p->{diff_time} * $k : undef;
    $u->{is_virtual} = $p->{is_virtual} ? 1 : 0;
    $dbh->do(_u $sql->update('contest_accounts',
        { diff_time => $u->{diff_time}, is_virtual => $u->{is_virtual} },
        { account_id => $p->{uid}, contest_id => $cid }
    ));
    $dbh->commit;
    msg($u->{diff_time} ? 1157 : 1158, $u->{team_name});
}

sub user_vdiff_frame
{
    my ($p) = @_;
    $is_jury or return;
    my $uid = $p->{uid} or return;

    init_template('user_vdiff.html.tt');

    my $u = $dbh->selectrow_hashref(q~
        SELECT A.id, A.team_name, CA.diff_time, CA.is_virtual,
            C.start_date AS contest_start,
            C.start_date + CA.diff_time AS contest_start_offset
        FROM accounts A
        INNER JOIN contest_accounts CA ON CA.account_id = A.id
        INNER JOIN contests C ON C.id = CA.contest_id
        WHERE A.id = ? AND CA.contest_id = ?~, { Slice => {} },
        $uid, $cid) or return;
    user_vdiff_save($p, $u);

    $t->param(
        user_submenu('user_vdiff', $uid),
        u => $u,
        formatted_diff_time => format_diff_time($u->{diff_time}, 1),
        title_suffix => $u->{team_name},
    );
}

1;
