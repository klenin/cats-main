package CATS::UI::UserDetails;

use strict;
use warnings;

use Storable qw(thaw);

use CATS::Constants;
use CATS::Countries;
use CATS::DB;
use CATS::Globals qw ($cid $is_jury $is_root $t $sid $uid $user);
use CATS::IP;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(auto_ext init_template url_f);
use CATS::Privileges;
use CATS::Settings qw($settings);
use CATS::Time;
use CATS::User;
use CATS::Utils qw(url_function);
use CATS::Web qw(param redirect url_param);

sub user_submenu {
    my ($selected, $user_id) = @_;
    my @m = (
        (
            $is_jury ?
                ({ href => url_f('users_edit', uid => $user_id), item => res_str(573), selected => 'edit' }) :
            $uid ?
                ({ href => url_f('profile'), item => res_str(518), selected => 'profile' }) :
                ()
        ),
        { href => url_f('user_stats', uid => $user_id), item => res_str(574), selected => 'user_stats' },
        (!$is_root ? () : (
            { href => url_f('user_settings', uid => $user_id), item => res_str(575), selected => 'user_settings' },
            { href => url_f('user_ip', uid => $user_id), item => res_str(576), selected => 'user_ip' },
        )),
        (!$is_jury && !$user->{is_site_org} ? () : (
            { href => url_f('user_vdiff', uid => $user_id), item => res_str(580), selected => 'user_vdiff' },
        )),
    );
    $_->{selected} = $_->{selected} eq $selected for @m;
    (submenu => \@m);
}

sub users_new_frame {
    init_template('users_new.html.tt');
    $is_jury or return;
    $t->param(
        login => CATS::User::generate_login,
        countries => \@CATS::Countries::countries,
        href_action => url_f('users'),
    );
}

sub users_edit_frame {
    my ($p) = @_;

    init_template('users_edit.html.tt');
    $is_jury or return;

    $p->{uid} or return;
    my $u = CATS::User->new->load($p->{uid}, [ qw(locked settings srole) ]) or return;
    $t->param(
        user_submenu('edit', $p->{uid}),
        title_suffix => $u->{team_name},
        %$u, privs => CATS::Privileges::unpack_privs($u->{srole}),
        id => $p->{uid},
        countries => \@CATS::Countries::countries,
        href_action => url_f('users'),
        href_impersonate => url_f('impersonate', uid => $p->{uid}));
}

sub user_stats_frame {
    my ($p) = @_;
    init_template('user_stats.html.tt');
    $p->{uid} or return;
    my $envelopes_sql = $is_root ?
        ', (SELECT COUNT(*) FROM reqs R WHERE R.account_id = A.id AND R.received = 0) AS envelopes' : '';
    my $u = $dbh->selectrow_hashref(qq~
        SELECT A.*, last_login AS last_login_date$envelopes_sql
        FROM accounts A WHERE A.id = ?~, { Slice => {} },
        $p->{uid}) or return;
    my $hidden_cond = $is_root ? '' :
        'AND C.is_hidden = 0 AND (CA.is_hidden = 0 OR CA.is_hidden IS NULL) AND C.defreeze_date < CURRENT_TIMESTAMP';
    my $contests = $dbh->selectall_arrayref(qq~
        SELECT C.id, C.title, CA.id AS caid, CA.is_jury,
            $CATS::Time::contest_start_offset_sql AS start_date,
            S.name AS site_name,
            (SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
                WHERE R.contest_id = C.id AND R.account_id = CA.account_id AND R.state = $cats::st_accepted
            ) AS accepted_count,
            (SELECT COUNT(*) FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.status < $cats::problem_st_hidden
            ) AS problem_count
        FROM contests C
        INNER JOIN contest_accounts CA ON CA.contest_id = C.id
        LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
        LEFT JOIN sites S ON S.id = CA.site_id
        WHERE
            CA.account_id = ? AND C.ctype = 0 $hidden_cond
        ORDER BY start_date DESC~,
        { Slice => {} }, $p->{uid});
    my $pr = sub { url_f(
        'console', uf => $p->{uid}, i_value => -1, se => 'user_stats', show_results => 1, search => $_[0], rows => 30
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
        $_->{href_problems} = url_function('problems', sid => $sid, cid => $_->{id});
        $_->{href_submits} = url_function('console', sid => $sid, cid => $_->{id},
            uf => $p->{uid}, i_value => -1, se => 'user_stats',
            show_results => 1, rows => 30, search => "contest_id=$_->{id}");
    }
    $t->param(
        user_submenu('user_stats', $p->{uid}),
        %$u, contests => $contests,
        CATS::IP::linkify_ip($u->{last_ip}),
        ($is_jury ? (href_edit => url_f('users_edit', uid => $p->{uid})) : ()),
        ($user->privs->{edit_sites} ? (
            href_sites => url_f('sites', search => "has_user($p->{uid})"),
            href_sites_org => url_f('sites', search => "has_org($p->{uid})"),
        ) : ()),
        href_all_problems => $pr->(''),
        href_solved_problems => $pr->('state=OK'),
        title_suffix => $u->{team_name},
    );
}

sub user_settings_frame {
    my ($p) = @_;
    init_template('user_settings.html.tt');
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
    display_settings(thaw($user_settings)) if $user_settings;
    $t->param(
        user_submenu('user_settings', $p->{uid}),
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

sub user_vdiff_load {
    my ($p) = @_;
    $dbh->selectrow_hashref(qq~
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
}

sub user_vdiff_save {
    my ($p, $u) = @_;
    $is_jury && $p->{save} or return;
    CATS::Time::set_diff_time($u, $p, 'diff') or return;
    CATS::Time::set_diff_time($u, $p, 'ext') or return;
    $u->{is_virtual} = $p->{is_virtual} ? 1 : 0;
    $dbh->do(_u $sql->update('contest_accounts',
        { diff_time => $u->{diff_time}, ext_time => $u->{ext_time}, is_virtual => $u->{is_virtual} },
        { account_id => $p->{uid}, contest_id => $cid }
    ));
    msg($u->{diff_time} ? 1157 : 1158, $u->{team_name});
    msg($u->{ext_time} ? 1162 : 1163, $u->{team_name});
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
    $dbh->do(qq~
        UPDATE contest_accounts CA
        SET CA.ext_time = COALESCE(CA.ext_time, 0) + ?
        WHERE CA.account_id = ? AND CA.contest_id = ?~, undef,
        $u->{since_finish}, $u->{id}, $cid);
    msg(1162, $u->{team_name});
    1;
}

sub user_vdiff_frame {
    my ($p) = @_;
    $is_jury || $user->{is_site_org} or return;
    $p->{uid} or return;

    init_template('user_vdiff.html.tt');

    my $u = user_vdiff_load($p) or return;
    if (user_vdiff_save($p, $u) || user_vdiff_finish_now($p, $u)) {
        $dbh->commit;
        $u = user_vdiff_load($p) or return;
    }

    $t->param(
        user_submenu('user_vdiff', $p->{uid}),
        u => $u,
        (map { +"formatted_$_" => CATS::Time::format_diff($u->{$_}, 1) }
            qw(diff_time site_diff_time ext_time site_ext_time since_start since_finish) ),
        can_finish_now => can_finish_now($u),
        title_suffix => $u->{team_name},
        href_site => url_f('contest_sites_edit', site_id => $u->{site_id}),
    );
}

sub registration_frame {
    my ($p) = @_;
    init_template('registration.html.tt');

    $t->param(countries => \@CATS::Countries::countries, href_login => url_f('login'));

    $p->{register} or return;

    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->{password1} = CATS::User::hash_password($u->{password1});
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
    if ($p->{clear}) {
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

1;
