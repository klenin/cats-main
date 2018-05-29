package CATS::UI::UserDetails;

use strict;
use warnings;

use Storable qw(thaw);

use CATS::Constants;
use CATS::Countries;
use CATS::DB;
use CATS::Form;
use CATS::Globals qw ($cid $is_jury $is_root $t $sid $uid $user);
use CATS::IP;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(auto_ext init_template url_f);
use CATS::Privileges;
use CATS::Settings qw($settings);
use CATS::Time;
use CATS::User;
use CATS::Utils qw(url_function);

sub user_submenu {
    my ($selected, $user_id, $site_id) = @_;
    $site_id //= 0;
    my $is_profile = $uid && $uid == $user_id;
    my @m = (
        (($is_root || $is_profile) && $selected eq 'user_contacts' ? (
            { href => url_f('user_contacts', uid => $user_id, new => 1), item => res_str(587), selected => '' }
        ) : ()),
        (
            $is_jury ?
                ({ href => url_f('users_edit', uid => $user_id), item => res_str(573), selected => 'edit' }) :
            $is_profile ?
                ({ href => url_f('profile'), item => res_str(518), selected => 'profile' }) :
                ()
        ),
        { href => url_f('user_stats', uid => $user_id), item => res_str(574), selected => 'user_stats' },
        (!$is_root ? () : (
            { href => url_f('user_settings', uid => $user_id), item => res_str(575), selected => 'user_settings' },
        )),
        { href => url_f('user_contacts', uid => $user_id), item => res_str(586), selected => 'user_contacts' },
        ($is_jury || $user->{is_site_org} && (!$user->{site_id} || $user->{site_id} == $site_id) ? (
            { href => url_f('user_vdiff', uid => $user_id), item => res_str(580), selected => 'user_vdiff' },
            { href => url_f('user_ip', uid => $user_id), item => res_str(576), selected => 'user_ip' },
        ) : ()),
    );
    $_->{selected} = $_->{selected} eq $selected for @m;
    (submenu => \@m);
}

sub users_new_frame {
    my ($p) = @_;

    init_template($p, 'users_new.html.tt');
    $is_jury or return;
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

    $p->{uid} or return;
    my $u = CATS::User->new->contest_fields([ 'site_id' ])->load($p->{uid}, [ qw(locked settings srole) ])
        or return;
    $t->param(
        user_submenu('edit', $p->{uid}, $u->{site_id}),
        title_suffix => $u->{team_name},
        %$u, privs => CATS::Privileges::unpack_privs($u->{srole}),
        id => $p->{uid},
        countries => \@CATS::Countries::countries,
        href_action => url_f('users'),
        href_impersonate => url_f('impersonate', uid => $p->{uid}));
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
    my $hidden_cond = $is_root ? '' :
        'AND C.is_hidden = 0 AND (CA.is_hidden = 0 OR CA.is_hidden IS NULL) ' .
        'AND C.defreeze_date < CURRENT_TIMESTAMP';
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
        user_submenu('user_stats', $p->{uid}, $u->{site_id}),
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

sub display_settings {
    my ($s) = @_;
    $t->param(settings => $s);
    $is_root or return;
    $t->param(settings_dump => CATS::Settings::as_dump($s));
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
    display_settings(thaw($user_settings)) if $user_settings;
    my $site_id = $is_jury ? 0 : $dbh->selectrow_array(q~
        SELECT CA.site_id FROM contest_accounts CA
        WHERE CA.account_id = ? AND CA.contest_id = ?~, undef,
        $p->{uid}, $cid);
    $t->param(
        user_submenu('user_settings', $p->{uid}, $site_id),
        team_name => $team_name,
        title_suffix => $team_name,
    );
}

sub user_ip_frame {
    my ($p) = @_;
    init_template($p, 'user_ip.html.tt');
    $is_jury || $user->{is_site_org} or return;
    $p->{uid} or return;
    my $u = CATS::User->new->contest_fields([ 'site_id' ])->load($p->{uid}) or return;
    my $cond = $is_root ? '' : ' AND CA.contest_id = ?';
    my $events = $dbh->selectall_arrayref(qq~
        SELECT MAX(E.ts) AS ts, E.ip FROM events E
        LEFT JOIN reqs R ON R.id = E.id
        LEFT JOIN contest_accounts CA ON CA.account_id = E.account_id AND CA.contest_id = R.contest_id
        WHERE E.account_id = ?$cond
        GROUP BY E.ip ORDER BY 1 DESC~,
        { Slice => {} }, $p->{uid}, ($is_root ? () : $cid));
    unshift @$events, { ts => $u->{last_login}, ip => $u->{last_ip } } if $is_root;
    for my $e (@$events) {
        my %linkified = CATS::IP::linkify_ip($e->{ip});
        $e->{$_} = $linkified{$_} for keys %linkified;
    }
    $t->param(
        user_submenu('user_ip', $p->{uid}, $u->{site_id}),
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

    init_template($p, 'user_vdiff.html.tt');

    my $u = user_vdiff_load($p) or return;
    if (user_vdiff_save($p, $u) || user_vdiff_finish_now($p, $u)) {
        $dbh->commit;
        $u = user_vdiff_load($p) or return;
    }

    $t->param(
        user_submenu('user_vdiff', $p->{uid}, $u->{site_id}),
        u => $u,
        (map { +"formatted_$_" => CATS::Time::format_diff($u->{$_}, 1) }
            qw(diff_time site_diff_time ext_time site_ext_time since_start since_finish) ),
        can_finish_now => can_finish_now($u),
        title_suffix => $u->{team_name},
        href_site => url_f('contest_sites_edit', site_id => $u->{site_id}),
    );
}

sub user_contact_fields() {qw(account_id contact_type_id handle is_public is_actual)}

my $user_contact_form = CATS::Form->new({
    table => 'contacts',
    fields => [ map +{ name => $_ }, user_contact_fields ],
    templates => { edit_frame => 'user_contacts_edit.html.tt' },
    href_action => 'user_contacts',
});

sub user_contacts_frame {
    my ($p) = @_;

    init_template($p, 'user_contacts.html.tt');
    $p->{uid} or return;

    my $is_profile = $uid && $uid == $p->{uid};
    if ($is_root || $is_profile) {
        $p->{new} || $p->{edit} and return $user_contact_form->edit_frame($p, after => sub {
            $_[0]->{contact_types} = $dbh->selectall_arrayref(q~
                SELECT id AS "value", name AS "text" FROM contact_types ORDER BY name~, { Slice => {} });
            unshift @{$_[0]->{contact_types}}, {};
        }, href_action_params => [ uid => $p->{uid} ]);
        $user_contact_form->edit_delete(id => $p->{delete}, descr => 'handle', msg => 1071);
        $p->{edit_save} and $user_contact_form->edit_save($p, before => sub {
            $_[0]->{account_id} = $p->{uid};
        }) and msg(1072, Encode::decode_utf8($p->{handle}));
    }

    init_template($p, 'user_contacts.html.tt');
    my $lv = CATS::ListView->new(name => 'user_contacts');
    my ($user_name, $user_site) = $is_profile ? ($user->{name}, $user->{site_id}) :
        @{CATS::User->new->contest_fields([ 'site_id' ])->load($p->{uid}) // {}}{qw(team_name site_id)};
    $user_name or return;

    $lv->define_columns(url_f('user_contacts'), 0, 0, [
        { caption => res_str(642), order_by => 'type_name', width => '20%' },
        { caption => res_str(657), order_by => 'handle', width => '30%' },
        ($is_root || $is_profile ?
            ({ caption => res_str(669), order_by => 'is_public', width => '15%', col => 'Ip' }) : ()),
        { caption => res_str(670), order_by => 'is_actual', width => '15%', col => 'Ia' },
    ]);
    $lv->define_db_searches([ user_contact_fields ]);
    my $public_cond = $is_root || $is_profile ? '' : ' AND C.is_public = 1';
    my $sth = $dbh->prepare(qq~
        SELECT C.id, C.contact_type_id, C.handle, C.is_public, C.is_actual, CT.name AS type_name, CT.url
        FROM contacts C
        INNER JOIN contact_types CT ON CT.id = C.contact_type_id
        WHERE C.account_id = ?$public_cond~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($p->{uid}, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        (
            ($is_root || $is_profile ? (
                href_edit => url_f('user_contacts', edit => $row->{id}, uid => $p->{uid}),
                href_delete => url_f('user_contacts', 'delete' => $row->{id}, uid => $p->{uid})) : ()),
            %$row,
            ($row->{url} ? (href_contact => sprintf $row->{url}, CATS::Utils::escape_url($row->{handle})) : ()),
        );
    };
    $lv->attach(url_f('user_contacts'), $fetch_record, $sth, { page_params => { uid => $p->{uid} } });
    $t->param(
        user_submenu('user_contacts', $p->{uid}, $user_site),
        title_suffix => res_str(586),
        problem_title => $user_name,
    );
}

sub registration_frame {
    my ($p) = @_;
    init_template($p, 'registration.html.tt');

    $t->param(countries => \@CATS::Countries::countries, href_login => url_f('login'));

    $p->{register} or return;

    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->{password1} = CATS::User::hash_password($u->{password1});
    $u->insert(undef, save_settings => 1) or return;
    $t->param(successfully_registred => 1);
}

sub profile_frame {
    my ($p) = @_;
    init_template($p, auto_ext('user_profile', $p->{json}));
    $uid or return;
    if ($p->{clear}) {
        $settings = {};
        msg(1029, $user->{name});
    }
    CATS::User::profile_save($p) if $p->{edit_save};

    my $u = CATS::User->new->load($uid) or return;
    my ($is_some_jury) = $is_jury || $dbh->selectrow_array(q~
        SELECT CA.contest_id FROM contest_accounts CA WHERE CA.account_id = ? AND CA.is_jury = 1~, undef,
        $uid);
    my ($email) = $dbh->selectrow_array(q~
        SELECT LIST(C.handle) FROM contacts C
        WHERE C.account_id = ? AND C.contact_type_id = ? AND C.is_public = 1~, undef,
        $uid, $CATS::Globals::contact_email);
    $t->param(
        user_submenu('profile', $uid, $user->{site_id}),
        countries => \@CATS::Countries::countries,
        href_action => url_f('users'),
        title_suffix => res_str(518),
        profile_langs => [ map { href => url_f('profile', lang => $_), name => $_ }, @cats::langs ],
        is_some_jury => $is_some_jury,
        %$u,
        email => $email,
    );
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
    $p->redirect(url_function 'contests', sid => $new_sid, cid => $cid);
}

1;
