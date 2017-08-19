package CATS::UI::Users;

use strict;
use warnings;

use Encode;
use Storable qw(freeze thaw);

use CATS::Constants;
use CATS::Countries;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t $uid $user);
use CATS::IP;
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(auto_ext init_template url_f);
use CATS::Privileges;
use CATS::Settings qw($settings);
use CATS::Time;
use CATS::User;
use CATS::Utils qw(url_function date_to_iso);
use CATS::Web qw(param redirect url_param);

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
sub users_new_save {
    $is_jury or return;
    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->{password1} = $hash_password->($u->{password1});
    $u->insert($cid) or return;
}

sub user_submenu {
    my ($selected, $user_id) = @_;
    my @m = (
        (
            $is_jury ?
                ({ href => url_f('users', edit => $user_id), item => res_str(573), selected => 'edit' }) :
            $uid ?
                ({ href => url_f('profile'), item => res_str(518), selected => 'profile' }) :
                ()
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

sub users_edit_frame {
    init_template('users_edit.html.tt');

    my $id = url_param('edit') or return;
    my $u = CATS::User->new->load($id, [ qw(locked settings srole) ]) or return;
    $t->param(
        user_submenu('edit', $id),
        title_suffix => $u->{team_name},
        %$u, privs => CATS::Privileges::unpack_privs($u->{srole}),
        id => $id,
        countries => \@CATS::Countries::countries,
        href_action => url_f('users'),
        href_impersonate => url_f('impersonate', uid => $id));
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

sub users_edit_save {
    my $u = CATS::User->new->parse_params;
    if (!$is_root) {
        delete $u->{restrict_ips};
    }
    # Simple $is_jury check is insufficient since jury member
    # can add any team to his contest.
    my $set_password = param('set_password') && $is_root;
    my $id = param('id');
    my $old_user = $id ? CATS::User->new->load($id, [ qw(settings srole) ]) : undef;
    # Only admins may edit other admins.
    return if !$is_root && CATS::Privileges::unpack_privs($old_user->{srole})->{is_root};

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

sub users_import_frame {
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

sub registration_frame {
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

sub profile_save {
    my $u = CATS::User->new->parse_params;
    if (!$is_root) {
        delete $u->{restrict_ips};
    }
    my $set_password = param('set_password');

    $u->validate_params(validate_password => $set_password, id => $uid) or return;
    update_settings($settings) or return;
    prepare_password($u, $set_password);
    $dbh->do(_u $sql->update('accounts', { %$u }, { id => $uid }));
    $dbh->commit;
}

sub display_settings {
    my ($s) = @_;
    $t->param(settings => $s);
    $is_root or return;
    $t->param(settings_dump => CATS::Settings::as_dump($s));
}

sub profile_frame {
    my ($p) = @_;
    init_template(auto_ext('user_profile', $p->{json}));
    $uid or return;
    if (defined $p->{clear}) {
        $settings = {};
        msg(1029, $user->{name});
    }
    profile_save if defined $p->{edit_save};

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
        is_some_jury => $is_some_jury,
        %$u);
    display_settings($settings);
}

sub users_delete {
    my $caid = url_param('delete');
    my ($aid, $srole, $name) = $dbh->selectrow_array(q~
        SELECT A.id, A.srole, A.team_name FROM accounts A
            INNER JOIN contest_accounts CA ON A.id = CA.account_id
            WHERE CA.id = ?~, undef,
        $caid);
    $aid or return;
    $name = Encode::decode_utf8($name);
    CATS::Privileges::is_root($srole) and return msg(1095, $name);

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

sub impersonate_frame {
    my ($p) = @_;
    $is_root or return;
    my $new_user_id = $p->{uid} or return;
    my $new_sid = CATS::User::make_sid;
    $dbh->selectrow_array(q~
        SELECT 1 FROM accounts WHERE id = ?~, undef, $new_user_id) or return;
    $dbh->do(q~
        UPDATE accounts SET last_ip = ?, sid = ? WHERE id = ?~, undef,
        CATS::IP::get_ip, $new_sid, $new_user_id);
    $dbh->commit;
    redirect(url_function('contests', sid => $new_sid, cid => $cid));
}

sub users_add_participants_frame {
    my ($p) = @_;
    $is_jury or return;
    init_template('users_add_participants.html.tt');
    CATS::User::register_by_login($p->{logins_to_add}, $cid, $p->{make_jury}) if $p->{by_login};
    CATS::User::copy_from_contest($p->{source_cid}, $p->{include_ooc}) if $p->{from_contest};
    my $contests = $dbh->selectall_arrayref(q~
        SELECT C.id, C.title FROM contests C
        WHERE C.id <> ? AND EXISTS (
            SELECT 1 FROM contest_accounts CA
            WHERE CA.contest_id = C.id AND CA.account_id = ? AND CA.is_jury = 1)
            ORDER BY C.start_date DESC~, { Slice => {} },
        $cid, $uid);
    $t->param(
        href_action => url_f('users_add_participants'),
        title_suffix => res_str(584),
        contests => $contests,
    );
}

sub users_frame {
    my ($p) = @_;

    if ($is_jury) {
        return CATS::User::new_frame if defined url_param('new');
        return users_edit_frame if defined url_param('edit');
    }

    my $lv = CATS::ListView->new(
        name => 'users' . ($contest->is_practice ? '_practice' : ''),
        array_name => 'users',
        template => auto_ext('users'));
    $t->param(title_suffix => res_str(526));

    if ($is_jury) {
        users_delete if defined url_param('delete');
        users_new_save if defined param('new_save');
        users_edit_save if defined param('edit_save');

        CATS::User::save_attributes_jury if $p->{save_attributes};
        CATS::User::set_tag(user_set => [ param('sel') ], tag => $p->{tag_to_set})
            if $p->{set_tag};

        if ($p->{send_message} && ($p->{message_text} // '') ne '') {
            my $contest_id = $is_root && $p->{send_all_contests} ? undef : $cid;
            if ($p->{send_all}) {
                CATS::User::send_broadcast(message => $p->{message_text}, contest_id => $contest_id);
                msg(1058);
            }
            else {
                my $count = CATS::User::send_message(
                    user_set => [ param('sel') ], message => $p->{message_text}, contest_id => $contest_id);
                msg(1057, $count);
            }
            $dbh->commit;
        }
    }
    elsif ($user->{is_site_org}) {
        CATS::User::save_attributes_org if $p->{save_attributes};
    }

    if ($is_jury || $user->{is_site_org}) {
        CATS::User::set_site(user_set => [ param('sel') ], site_id => $p->{site_id}) if $p->{set_site};
        # Consider site_org without site_id as 'all sites organizer'.
        my ($site_cond, @site_param) = $is_jury || !$user->{site_id} ? ('') : (' AND S.id = ?', $user->{site_id});
        $t->param(sites => $dbh->selectall_arrayref(qq~
            SELECT S.id, S.name
            FROM sites S INNER JOIN contest_sites CS ON CS.site_id = S.id
            WHERE CS.contest_id = ?$site_cond
            ORDER BY S.name~, { Slice => {} },
            $cid, @site_param));
    }

    my @cols = (
        ($is_jury ?
            { caption => res_str(616), order_by => 'login', width => '20%' } : ()),
        { caption => res_str(608), order_by => 'team_name', width => '30%' },
        { caption => res_str(627), order_by => 'COALESCE(S.name, A.city)', width => '20%', col => 'Si' },
        { caption => res_str(629), order_by => 'tag', width => '5%', col => 'Tg' },
        ($is_jury || $user->{is_site_org} ? (
            { caption => res_str(612), order_by => 'is_ooc', width => '1%' },
            { caption => res_str(613), order_by => 'is_remote', width => '1%' },
            { caption => res_str(610), order_by => 'is_site_org', width => '1%' },
        ) : ()),
        ($is_jury ? (
            { caption => res_str(611), order_by => 'is_jury', width => '1%' },
            { caption => res_str(614), order_by => 'is_hidden', width => '1%' },
        ) : ()),
        { caption => res_str(607), order_by => 'country', width => '5%', col => 'Fl' },
        { caption => res_str(609), order_by => 'rating', width => '5%', col => 'Rt' },
        { caption => res_str(632), order_by => 'diff_time', width => '5%', col => 'Dt' },
    );

    $lv->define_columns(url_f('users'), $is_jury ? 3 : 2, 1, \@cols);

    return if !$is_jury && param('json') && $contest->is_practice;

    my @fields = qw(
        A.id A.country A.motto A.login A.team_name A.city
        CA.is_jury CA.is_ooc CA.is_remote CA.is_hidden CA.is_site_org
        CA.is_virtual CA.diff_time CA.ext_time CA.tag);
    $lv->define_db_searches(\@fields);
    $lv->define_db_searches({
        'CA.id' => 'CA.id',
        is_judge => q~
            CASE WHEN EXISTS (SELECT * FROM judges J WHERE J.account_id = A.id) THEN 1 ELSE 0 END~,
        site_name => 'S.name',
        site_id => 'COALESCE(CA.site_id, 0)',
    });
    $lv->define_enums({ site_id => { 'my' => $user->{site_id} } }) if $user->{site_id};

    my $fields = join ', ', @fields;
    my $rating_sql = !$lv->visible_cols->{Rt} ? 'NULL' : qq~
        SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
            WHERE R.state = $cats::st_accepted AND R.account_id = A.id AND R.contest_id = C.id~ .
        ($is_jury ? '' : ' AND (R.submit_time < C.freeze_date OR C.defreeze_date < CURRENT_TIMESTAMP)');

    my $sql = sprintf qq~
        SELECT ($rating_sql) AS rating, CA.id, $fields, CA.site_id, S.name AS site_name
        FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id
            INNER JOIN contests C ON CA.contest_id = C.id
            LEFT JOIN sites S ON S.id = CA.site_id
        WHERE C.id = ?%s %s ~ . $lv->order_by,
        ($is_jury || $user->{is_site_org} && !$user->{site_id} ? '' :
        $user->{is_site_org} ? ' AND (CA.is_hidden = 0 OR CA.site_id = ?)' :
        ' AND CA.is_hidden = 0'),
        $lv->maybe_where_cond;

    my $c = $dbh->prepare($sql);
    $c->execute(
        $cid,
        (!$is_jury && $user->{is_site_org} && $user->{site_id} ? $user->{site_id} : ()),
        $lv->where_params);

    my $fetch_record = sub {
        my (
            $accepted, $caid, $aid, $country_abbr, $motto, $login, $team_name, $city,
            $jury, $ooc, $remote, $hidden, $site_org, $virtual, $diff_time, $ext_time,
            $tag, $site_id, $site_name
        ) = $_[0]->fetchrow_array
            or return ();
        my ($country, $flag) = CATS::Countries::get_flag($country_abbr);
        return (
            href_delete => url_f('users', delete => $caid),
            href_edit => url_f('users', edit => $aid),
            href_stats => url_f('user_stats', uid => $aid),
            ($user->privs->{edit_sites} && $site_id ? (href_site => url_f('sites', edit => $site_id)) : ()),
            ($is_jury && $site_id ?
                (href_contest_site => url_f('contest_sites_edit', site_id => $site_id)) : ()),
            ($is_jury ? (href_vdiff => url_f('user_vdiff', uid => $aid)) : ()),

            motto => $motto,
            id => $caid,
            account_id => $aid,
            login => $login,
            team_name => $team_name,
            city => $city,
            tag => $tag,
            site_id => $site_id,
            site_name => $site_name,
            country => $country,
            flag => $flag,
            accepted => $accepted,
            jury => $jury,
            hidden => $hidden,
            ooc => $ooc,
            remote => $remote,
            site_org => $site_org,
            editable_attrs =>
                ($is_jury || (!$user->{site_id} || $user->{site_id} == $site_id) && $uid && $aid != $uid),
            virtual => $virtual,
            formatted_time => CATS::Time::format_diff_ext($diff_time, $ext_time, 1),
         );
    };

    $lv->attach(url_f('users'), $fetch_record, $c);

    if ($is_jury)  {
        $t->param(submenu => [
            { href => url_f('users', new => 1), item => res_str(541) },
            { href => url_f('users_import'), item => res_str(564) },
            { href => url_f('users_add_participants'), item => res_str(584) },
            ($is_root ?
                { href => url_f('users_all_settings'), item => res_str(575) } : ()),
        ]);
    }
    elsif ($user->{is_site_org}) {
        $t->param(submenu => [
            ($user->{site_id} ?
                { href => url_f('users', search => 'site_id=my'), item => res_str(582) } : ()),
            { href => url_f('users', search => 'site_id=0'), item => res_str(583) },
        ]);
    }

    $c->finish;
}

sub user_stats_frame {
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
        SELECT C.id, C.title, CA.id AS caid, CA.is_jury,
            $CATS::Time::contest_start_offset_sql AS start_date,
            (SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
                WHERE R.contest_id = C.id AND R.account_id = CA.account_id AND R.state = $cats::st_accepted
            ) AS accepted_count,
            (SELECT COUNT(*) FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.status < $cats::problem_st_hidden
            ) AS problem_count
        FROM contests C
        INNER JOIN contest_accounts CA ON CA.contest_id = C.id
        LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
        WHERE
            CA.account_id = ? AND C.ctype = 0 $hidden_cond
        ORDER BY start_date DESC~,
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
        %$u, contests => $contests,
        CATS::IP::linkify_ip($u->{last_ip}),
        ($is_jury ? (href_edit => url_f('users', edit => $uid)) : ()),
        href_all_problems => $pr->(''),
        href_solved_problems => $pr->('state=OK'),
        title_suffix => $u->{team_name},
    );
}

sub users_all_settings_frame {
    my ($p) = @_;

    init_template('users_settings.html.tt');
    $is_root or return;

    my $lv = CATS::ListView->new(
        name => 'users_all_settings', template => 'users_all_settings.html.tt',
        extra_settings => { selector => '' });

    $lv->define_columns(url_f('users_all_settings'), 0, 0, [
        { caption => res_str(616), order_by => 'login', width => '15%' },
        { caption => res_str(608), order_by => 'team_name', width => '15%' },
        { caption => res_str(660), order_by => 'last_login', width => '15%' },
        { caption => res_str(661), order_by => 'team_name', width => '55%' },
    ]);
    $lv->define_db_searches([ qw(id login team_name last_login settings) ]);
    my $sth = $dbh->prepare(q~
        SELECT A.id, A.login, A.team_name, A.last_login, A.settings
        FROM accounts A
        INNER JOIN contest_accounts CA ON A.id = CA.account_id
        WHERE CA.contest_id = ?~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $selector = $lv->settings->{selector};
    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        my $all_settings = thaw($row->{settings});
        if ($selector) {
            for (split /\./, $selector) {
                $all_settings = $all_settings->{$_} or last;
            }
        }
        my $full = CATS::Settings::as_dump($all_settings, 0);
        my $short = length($full) < 120 ? $full : substr($full, 0, 120) . '...';
        (
            href_edit => url_f('users', edit => $row->{id}),
            href_settings => url_f('user_settings', uid => $row->{id}),
            %$row,
            settings_short => $short,
            settings_full => $full,
        );
    };
    $lv->attach(url_f('users_all_settings'), $fetch_record, $sth);
    $t->param(title_suffix => res_str(575));
}

sub user_settings_frame {
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

sub user_ip_frame {
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

sub user_vdiff_save {
    my ($p, $u) = @_;
    $p->{save} or return;
    CATS::Time::set_diff_time($u, $p, 'diff') or return;
    CATS::Time::set_diff_time($u, $p, 'ext') or return;
    $u->{is_virtual} = $p->{is_virtual} ? 1 : 0;
    $dbh->do(_u $sql->update('contest_accounts',
        { diff_time => $u->{diff_time}, ext_time => $u->{ext_time}, is_virtual => $u->{is_virtual} },
        { account_id => $p->{uid}, contest_id => $cid }
    ));
    ($u->{contest_start_offset}, $u->{contest_finish_offset}) = $dbh->selectrow_array(qq~
        SELECT
            $CATS::Time::contest_start_offset_sql,
            $CATS::Time::contest_finish_offset_sql
        FROM contest_accounts CA
        INNER JOIN contests C ON C.id = CA.contest_id
        LEFT JOIN contest_sites CS ON CS.site_id = CA.site_id AND CS.contest_id = CA.contest_id
        WHERE CA.account_id = ? AND CA.contest_id = ?~, undef,
        $u->{id}, $cid) or return;
    $dbh->commit;
    msg($u->{diff_time} ? 1157 : 1158, $u->{team_name});
    msg($u->{ext_time} ? 1162 : 1163, $u->{team_name});
}

sub user_vdiff_frame {
    my ($p) = @_;
    $is_jury or return;
    $p->{uid} or return;

    init_template('user_vdiff.html.tt');

    my $u = $dbh->selectrow_hashref(qq~
        SELECT A.id, A.team_name, CA.diff_time, CA.ext_time, CA.is_virtual, CA.site_id,
            C.start_date AS contest_start,
            $CATS::Time::contest_start_offset_sql AS contest_start_offset,
            C.finish_date AS contest_finish,
            $CATS::Time::contest_finish_offset_sql AS contest_finish_offset,
            CS.diff_time AS site_diff_time, CS.ext_time AS site_ext_time,
            C.start_date + CS.diff_time AS site_contest_start_offset,
            C.finish_date + CS.diff_time + CS.ext_time AS site_contest_finish_offset,
            S.name AS site_name
        FROM accounts A
        INNER JOIN contest_accounts CA ON CA.account_id = A.id
        INNER JOIN contests C ON C.id = CA.contest_id
        LEFT JOIN contest_sites CS ON CS.site_id = CA.site_id AND CS.contest_id = CA.contest_id
        LEFT JOIN sites S ON S.id = CA.site_id
        WHERE A.id = ? AND CA.contest_id = ?~, { Slice => {} },
        $p->{uid}, $cid) or return;
    user_vdiff_save($p, $u);

    $t->param(
        user_submenu('user_vdiff', $p->{uid}),
        u => $u,
        (map { +"formatted_$_" => CATS::Time::format_diff($u->{$_}, 1) }
            qw(diff_time site_diff_time ext_time site_ext_time) ),
        title_suffix => $u->{team_name},
        href_site => url_f('contest_sites_edit', site_id => $u->{site_id}),
    );
}

1;
