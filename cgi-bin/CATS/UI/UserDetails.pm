package CATS::UI::UserDetails;

use strict;
use warnings;

use Storable;

use CATS::Constants;
use CATS::Contest::Participate;
use CATS::Countries;
use CATS::DB qw(:DEFAULT $db);
use CATS::Form;
use CATS::Globals qw ($cid $is_jury $is_root $t $uid $user);
use CATS::IP;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f url_f_cid);
use CATS::Privileges;
use CATS::Settings qw($settings);
use CATS::Time;
use CATS::User;
use CATS::Utils qw(url_function);

sub _settings_validated {
    my ($p) = @_;
    $p->{edit_save} && $t->{vars}->{$CATS::User::settings_form->{template_var}}->{is_validated};
}

sub users_new_frame {
    my ($p) = @_;

    init_template($p, 'users_new.html.tt');
    $is_jury or return;

    my $s = $p->{$CATS::User::settings_form->{id_param}} = {};
    $CATS::User::settings_form->edit_frame($p);
    $t->param(
        login => CATS::User::generate_login,
        countries => \@CATS::Countries::countries,
        href_action => url_f('users'),
    );
}

sub users_edit_frame {
    my ($p) = @_;

    init_template($p, 'users_edit.html.tt');
    $is_jury or return;

    my $id = $p->{uid} || $p->{id} or return;
    my $u = CATS::User->new->contest_fields([ 'site_id' ])->
        load($id, [ qw(locked settings srole last_ip) ])
        or return;

    my $s = $p->{$CATS::User::settings_form->{id_param}} = $u->{settings} // {};
    delete $u->{settings};
    $CATS::User::settings_form->edit_frame($p);
    CATS::User::edit_save($p, $s) if $p->{edit_save} && _settings_validated($p);

    $t->param(
        CATS::User::submenu('edit', $id, $u->{site_id}),
        title_suffix => $u->{team_name},
        %$u, privs => CATS::Privileges::unpack_privs($u->{srole}),
        priv_names => CATS::Privileges::ui_names,
        id => $id,
        countries => \@CATS::Countries::countries,
        href_action => url_f('users_edit'),
        href_impersonate => url_f('impersonate', uid => $id));
}

sub _tokens {
    my ($p) = @_;
    $is_root or return;
    if ($p->{make_token}) {
        CATS::User::make_token($p->{uid});
    }
    my $tokens = $dbh->selectall_arrayref(q~
        SELECT token, last_used, usages_left, referer FROM account_tokens
        WHERE account_id = ?~, { Slice => {} },
        $p->{uid});
    for (@$tokens) {
        $_->{href_login} = url_function('login', token => $_->{token});
        $_->{last_used} = $db->format_date($_->{last_used});
    }
    $t->param(
        href_make_token => url_f('user_stats', uid => $p->{uid}),
        tokens => $tokens,
    );
}

sub user_stats_frame {
    my ($p) = @_;
    init_template($p, 'user_stats.html.tt');
    $p->{uid} or return;
    my $envelopes_sql = $is_root ?
        ', (SELECT COUNT(*) FROM reqs R WHERE R.account_id = A.id AND R.received = 0) AS envelopes' : '';
    my $u = $dbh->selectrow_hashref(qq~
        SELECT A.*, last_login AS last_login_date,
            (SELECT CA.site_id FROM contest_accounts CA
                WHERE CA.account_id = A.id AND CA.contest_id = ?) AS site_id
            $envelopes_sql
        FROM accounts A WHERE A.id = ?~, { Slice => {} },
        $cid, $p->{uid}) or return;
    $u->{last_login_date} = $db->format_date($u->{last_login_date});
    my $hidden_cond = $is_root ? '' :
        'AND C.is_hidden = 0 AND (CA.is_hidden = 0 OR CA.is_hidden IS NULL) ' .
        'AND C.defreeze_date < CURRENT_TIMESTAMP';
    my $award_splitter = '#~#';
    my $contests = $dbh->selectall_arrayref(qq~
        SELECT C.id, C.title, CA.id AS caid, CA.is_jury, CA.is_ooc,
            $CATS::Time::contest_start_offset_sql AS start_date,
            S.name AS site_name,
            (SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
                WHERE R.contest_id = C.id AND R.account_id = CA.account_id AND R.state = $cats::st_accepted
            ) AS accepted_count,
            (SELECT COUNT(*) FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.status < $cats::problem_st_hidden
            ) AS problem_count,
            (SELECT LIST(AW.name || ',' || AW.color, '$award_splitter') FROM contest_account_awards CAA
                INNER JOIN awards AW ON AW.id = CAA.award_id
                WHERE CAA.ca_id = CA.id
            ) AS awards
        FROM contests C
        INNER JOIN contest_accounts CA ON CA.contest_id = C.id
        LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
        LEFT JOIN sites S ON S.id = CA.site_id
        WHERE
            CA.account_id = ? AND C.ctype = 0 $hidden_cond
        ORDER BY start_date DESC~,
        { Slice => {} }, $p->{uid});
    my $pr = sub { url_f(
        'console', uf => $p->{uid}, i_value => -1, se => 'user_stats',
        show_results => 1, search => $_[0], rows => 30
    ) };
    $u->{sites_count} = $dbh->selectrow_array(q~
        SELECT COUNT(DISTINCT site_id) FROM contest_accounts
        WHERE account_id = ?~, undef,
        $p->{uid});
    $u->{sites_org_count} = $dbh->selectrow_array(q~
        SELECT COUNT(DISTINCT site_id) FROM contest_accounts
        WHERE account_id = ? AND is_site_org = 1~, undef,
        $p->{uid});
    for (@$contests) {
        $_->{href_send_message} = url_f('send_message_box', caid => $_->{caid}) if $is_root;
        $_->{href_problems} = url_f_cid('problems', cid => $_->{id});
        $_->{href_submits} = url_f_cid('console', cid => $_->{id},
            uf => $p->{uid}, i_value => -1, se => 'user_stats',
            show_results => 1, rows => 30, search => "contest_id=$_->{id}");
        $_->{start_date} = $db->format_date($_->{start_date});
        $_->{awards} = [
            map /^(.+),(.*)$/ && { name => $1, color => $2 }, split $award_splitter, $_->{awards} // '' ];
    }

    my $groups_hidden_cond = $user->privs->{manage_groups} ? '' : q~ AND AGA.is_hidden = 0~;
    my $groups = $dbh->selectall_arrayref(q~
        SELECT AG.id, AG.name, AGA.date_start, AGA.is_admin, AGA.is_hidden FROM acc_groups AG
        INNER JOIN acc_group_accounts AGA ON AGA.acc_group_id = AG.id
        WHERE AGA.account_id = ?~ . $groups_hidden_cond, { Slice => {} },
        $p->{uid});
    for (@$groups) {
        $_->{href_acc_group_users} = url_f('acc_group_users', group => $_->{id}) if $is_root;
    }

    _tokens($p);
    $t->param(
        CATS::User::submenu('user_stats', $p->{uid}, $u->{site_id}),
        %$u, contests => $contests,
        groups => $groups,
        CATS::IP::linkify_ip($u->{last_ip}),
        ($is_jury ? (href_edit => url_f('users_edit', uid => $p->{uid})) : ()),
        ($user->privs->{edit_sites} ? (
            href_sites => url_f('sites', search => "has_user($p->{uid})"),
            href_sites_org => url_f('sites', search => "has_org($p->{uid})"),
        ) : ()),
        href_all_problems => $pr->(''),
        href_solved_problems => $pr->('state=OK'),
        href_contests => url_f(contests => search => "has_user($p->{uid})"),
        href_filtered_users => url_f(users => search => "id=$p->{uid}"),
        title_suffix => $u->{team_name},
    );
}

sub user_settings_frame {
    my ($p) = @_;
    init_template($p, 'user_settings.html.tt');
    $is_root && $p->{uid} or return;

    my $cleared;
    if ($p->{clear}) {
        $cleared = $dbh->do(q~
            UPDATE accounts SET settings = NULL WHERE id = ?~, undef,
            $p->{uid}
        ) and $dbh->commit;
    }

    my ($team_name, $user_settings) = $dbh->selectrow_array(q~
        SELECT team_name, settings FROM accounts WHERE id = ?~, undef,
        $p->{uid});

    msg(1029, $team_name) if $cleared;
    my $site_id = $is_jury ? 0 : $dbh->selectrow_array(q~
        SELECT CA.site_id FROM contest_accounts CA
        WHERE CA.account_id = ? AND CA.contest_id = ?~, undef,
        $p->{uid}, $cid);
    $t->param(
        CATS::User::submenu('user_settings', $p->{uid}, $site_id),
        team_name => $team_name,
        title_suffix => $team_name,
        settings_dump => $user_settings &&
            CATS::Settings::as_dump(eval { Storable::thaw($user_settings) } || {}),
    );
}

sub user_ip_frame {
    my ($p) = @_;
    init_template($p, 'user_ip.html.tt');
    $is_jury || $user->{is_site_org} or return;
    $p->{uid} or return;
    my $u = CATS::User->new->contest_fields([ qw(site_id last_login last_ip) ])->load($p->{uid}) or return;
    my $cond = $is_root ? '' : ' AND CA.contest_id = ?';
    my $events = $dbh->selectall_arrayref(qq~
        SELECT MAX(E.ts) AS ts, E.ip FROM events E
        LEFT JOIN reqs R ON R.id = E.id
        LEFT JOIN contest_accounts CA ON CA.account_id = E.account_id AND CA.contest_id = R.contest_id
        WHERE E.account_id = ?$cond
        GROUP BY E.ip ORDER BY 1 DESC~,
        { Slice => {} }, $p->{uid}, ($is_root ? () : $cid));
    unshift @$events, { ts => $u->{last_login}, ip => $u->{last_ip} } if $is_root;
    for (@$events) {
        $_->{ip} or next;
        $_->{is_tor} = CATS::IP::is_tor($_->{ip});
        last;
    }
    for my $e (@$events) {
        my %linkified = CATS::IP::linkify_ip($e->{ip});
        $e->{$_} = $linkified{$_} for keys %linkified;
        $e->{ts} = $db->format_date($e->{ts});
    }
    $t->param(
        CATS::User::submenu('user_ip', $p->{uid}, $u->{site_id}),
        %$u,
        events => $events,
        title_suffix => $u->{team_name},
    );
}

sub user_vdiff_load {
    my ($p) = @_;
    my $u = $dbh->selectrow_hashref(qq~
        SELECT A.id, A.team_name, CA.diff_time, CA.ext_time, CA.is_virtual, CA.site_id,
            C.start_date AS contest_start,
            $CATS::Time::contest_start_offset_sql AS contest_start_offset,
            CAST(CURRENT_TIMESTAMP - $CATS::Time::contest_start_offset_sql AS DOUBLE PRECISION) AS since_start,
            C.finish_date AS contest_finish,
            $CATS::Time::contest_finish_offset_sql AS contest_finish_offset,
            CAST(CURRENT_TIMESTAMP - $CATS::Time::contest_finish_offset_sql AS DOUBLE PRECISION) AS since_finish,
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
        $p->{uid}, $cid);
    $u->{$_} = $db->format_date($u->{$_})
        for qw(contest_start contest_start_offset contest_finish contest_finish_offset);
    $u;
}

my $new_start_fld = CATS::Field->new(
    name => 'new_start', caption => 817, validators => [ CATS::Field::date_time(allow_empty => 1) ]);

sub _set_diff_time_val {
    my ($u, $new_start) = @_;
    $new_start or return;
    my $msg = $new_start_fld->validate($new_start);
    die $msg if $msg;
    my $old_diff_time = $u->{diff_time};
    $u->{diff_time} = $dbh->selectrow_array(q~
        SELECT CAST(? AS TIMESTAMP) - C.start_date FROM contests C WHERE C.id = ?~, undef,
        $new_start, $cid);
    ($old_diff_time // 'undef') ne ($u->{diff_time} // 'undef');
}

sub user_vdiff_save {
    my ($p, $u) = @_;
    $is_jury && $p->{save} or return;
    my ($changed_diff, $changed_ext);
    eval {
        $changed_diff =
            $p->{diff_time_method} eq 'diff' ? CATS::Time::set_diff_time($u, $p, 'diff') :
            $p->{diff_time_method} eq 'val' ? _set_diff_time_val($u, $p->{new_start}) :
            die "diff_time_method: $p->{diff_time_method}";
        $changed_ext = CATS::Time::set_diff_time($u, $p, 'ext');
        1;
    } or return CATS::Messages::msg_debug($@);
    $u->{is_virtual} = $p->{is_virtual} ? 1 : 0;
    $dbh->do(_u $sql->update('contest_accounts',
        { diff_time => $u->{diff_time}, ext_time => $u->{ext_time}, is_virtual => $u->{is_virtual} },
        { account_id => $p->{uid}, contest_id => $cid }
    ));
    $changed_diff and msg($u->{diff_time} ? 1157 : 1158, $u->{team_name});
    $changed_ext and msg($u->{ext_time} ? 1162 : 1163, $u->{team_name});
    1;
}

sub can_finish_now {
    my ($u) = @_;
    $u->{since_start} > 0 && $u->{since_finish} < 0 &&
        ($is_jury || !$user->{site_id} || $u->{site_id} == $user->{site_id});
}

sub user_vdiff_finish_now {
    my ($p, $u) = @_;
    ($is_jury || $user->{is_site_org}) && $p->{finish_now} && can_finish_now($u) or return;
    $dbh->do(q~
        UPDATE contest_accounts CA
        SET ext_time = COALESCE(CA.ext_time, 0) + ?
        WHERE CA.account_id = ? AND CA.contest_id = ?~, undef,
        $u->{since_finish}, $u->{id}, $cid);
    msg(1162, $u->{team_name});
    1;
}

sub user_vdiff_frame {
    my ($p) = @_;
    $is_jury || $user->{is_site_org} or return;
    $p->{uid} or return;

    init_template($p, 'user_vdiff.html.tt');

    my $u = user_vdiff_load($p) or return;
    if (user_vdiff_save($p, $u) || user_vdiff_finish_now($p, $u)) {
        $dbh->commit;
        $u = user_vdiff_load($p) or return;
    }

    $t->param(
        CATS::User::submenu('user_vdiff', $p->{uid}, $u->{site_id}),
        u => $u,
        diff_time_method => $p->{diff_time_method} || 'diff',
        new_start => $p->{new_start},
        new_start_fld => $new_start_fld,
        (map { +"formatted_$_" => CATS::Time::format_diff($u->{$_}, display_plus => 1) }
            qw(diff_time site_diff_time ext_time site_ext_time since_start since_finish) ),
        can_finish_now => can_finish_now($u),
        title_suffix => $u->{team_name},
        href_site => url_f('contest_sites_edit', site_id => $u->{site_id}),
    );
}

sub registration_frame {
    my ($p) = @_;
    init_template($p, 'registration.html.tt');

    $p->{$CATS::User::settings_form->{id_param}} = $settings;
    $CATS::User::settings_form->edit_frame($p);

    my $has_clist = @{$p->{clist}} > 0;
    $t->param(
        countries => \@CATS::Countries::countries,
        contest_names => $has_clist && $dbh->selectcol_arrayref(_u $sql->select(
            'contests', 'title', { id => $p->{clist}, is_hidden => 0 })),
        href_login => url_f('login'),
        href_login_available => url_function('api_login_available', login => ''),
    );

    $p->{register} or return;

    my $u = CATS::User->new->parse_params($p);
    $u->validate_params(validate_password => 1) or return;
    $u->{password1} = CATS::User::hash_password($u->{password1});
    $settings->{contests}->{filter} = 'my' if $has_clist;
    $u->insert(undef, save_settings => 1, commit => !$has_clist) or return;
    CATS::Contest::Participate::multi_online($u->{id}, $p->{clist});
    $t->param(successfully_registered => 1);
}

sub profile_frame {
    my ($p) = @_;
    init_template($p, 'user_profile');
    $uid or return;
    if ($p->{clear}) {
        $settings = {};
        msg(1029, $user->{name});
    }
    $p->{$CATS::User::settings_form->{id_param}} = $settings;
    $CATS::User::settings_form->edit_frame($p);
    CATS::User::profile_save($p) if $p->{edit_save} && _settings_validated($p);

    my $u = CATS::User->new->load($uid) or return;
    my ($is_some_jury) = $is_jury || $dbh->selectrow_array(q~
        SELECT CA.contest_id FROM contest_accounts CA WHERE CA.account_id = ? AND CA.is_jury = 1~, undef,
        $uid);
    my ($email) = $dbh->selectrow_array(q~
        SELECT LIST(C.handle) FROM contacts C
        WHERE C.account_id = ? AND C.contact_type_id = ? AND C.is_public = 1~, undef,
        $uid, $CATS::Globals::contact_email);
    $t->param(
        CATS::User::submenu('profile', $uid, $user->{site_id}),
        countries => \@CATS::Countries::countries,
        href_action => url_f('users'),
        title_suffix => res_str(518),
        profile_langs => [ map { href => url_f('profile', lang => $_), name => $_ }, @cats::langs ],
        is_some_jury => $is_some_jury,
        %$u,
        email => $email,
    );
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
    $p->redirect(url_function 'contests', sid => $new_sid, cid => $cid);
}

1;
