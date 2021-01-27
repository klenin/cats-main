package CATS::UI::Users;

use strict;
use warnings;

use Encode;
use Storable qw(freeze thaw);

use CATS::Constants;
use CATS::Countries;
use CATS::DB qw(:DEFAULT $db);
use CATS::Globals qw($cid $contest $is_jury $is_root $t $uid $user);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::Privileges;
use CATS::RankTable::Cache;
use CATS::Time;
use CATS::User;

sub users_submenu {
    if ($is_jury)  {
        submenu => [
            { href => url_f('users_new'), item => res_str(541), new => 1 },
            { href => url_f('users_import'), item => res_str(564) },
            { href => url_f('users_add_participants'), item => res_str(584) },
            ($is_root ?
                { href => url_f('users_all_settings'), item => res_str(575) } : ()),
        ];
    }
    elsif ($user->{is_site_org}) {
        submenu => [
            ($user->{site_id} ?
                { href => url_f('users', search => 'site_id=my'), item => res_str(582) } : ()),
            { href => url_f('users', search => 'site_id=0'), item => res_str(583) },
        ];
    }
    else {
        ();
    }
}

my %user_fields = (password => 'password1', map { $_ => $_ } CATS::User::param_names);

sub users_import_frame {
    my ($p) = @_;
    init_template($p, 'users_import.html.tt');
    $is_jury or return;
    my $contact_types = $dbh->selectall_hashref(q~
        SELECT id, name FROM contact_types~, 'name');
    $t->param(
        href_action => url_f('users_import'), title_suffix => res_str(564), users_submenu,
        contact_types => $contact_types, user_fields => \%user_fields);
    $p->{go} or return;

    my ($header, @lines) = split "\r\n", Encode::decode_utf8($p->{user_list});
    my ($i, @fields_idx, @field_names_idx, @contact_types_idx) = (0);
    for my $h (split "\t", $header) {
        if (my $uf = $user_fields{$h}) {
            push @fields_idx, $i;
            push @field_names_idx, $uf;
        }
        elsif (my $ct = $contact_types->{$h}) {
            push @contact_types_idx, [ $i, $ct->{id} ];
        }
        $i++;
    }

    my @report;
    my $count = 0;
    for my $line (@lines) {
        my @cols = split "\t", $line;
        my $u = CATS::User->new;
        @$u{@field_names_idx} = @cols[@fields_idx];
        my ($user_id) = $dbh->selectrow_array(q~
            SELECT id FROM accounts WHERE login = ?~, undef,
            $u->{login});
        my $r = $user_id ? 'exists' :
        eval {
            $u->{password1} = CATS::User::hash_password(Encode::encode_utf8($u->{password1}))
                if $u->{password1};
            $u->insert($contest->{id}, is_ooc => 0, commit => 0);
            $count++;
            'ok';
        } || $@;
        my $contact_count = 0;
        for my $ct (@contact_types_idx) {
            my ($i, $ct_id) = @$ct;
            $contact_count += $dbh->do(_u $sql->insert('contacts', {
                id => new_id,
                account_id => $u->{id}, contact_type_id => $ct_id,
                handle => $cols[$i], is_actual => 1,
            }));
        }
        push @report, "$u->{team_name} -- $r (contacts=$contact_count)";
    }

    $p->{do_import} ? $dbh->commit : $dbh->rollback;
    push @report, ($p->{do_import} ? 'Import' : 'Test') . " complete: $count";
    $t->param(report => join "\n", @report);
}

sub users_delete {
    my ($p) = @_;
    my $caid = $p->{delete_user} or return;
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
    CATS::RankTable::Cache::remove($cid);
}

sub users_add_participants_frame {
    my ($p) = @_;
    $is_jury or return;
    init_template($p, 'users_add_participants.html.tt');
    if ($p->{by_login}) {
        my $aids = CATS::User::register_by_login($p->{logins_to_add}, $cid,
            $p->{make_jury} && $user->privs->{grant_jury});
        if ($aids) {
            $t->param(href_view_added => url_f(users => search => join ',', map "id=$_", @$aids));
        }
        else {
            $t->param(logins_to_add => Encode::decode_utf8($p->{logins_to_add}));
        }
    }
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
        users_submenu,
        contests => $contests,
        href_find_users => url_f('api_find_users', in_contest => 0),
    );
}

sub _contact_field_sql {
    qq~(
        SELECT CT.handle FROM contacts CT
        WHERE CT.account_id = A.id AND CT.contact_type_id = $_[0]->{id}
        ORDER BY is_actual DESC $db->{LIMIT} 1)~,
}

sub users_frame {
    my ($p) = @_;

    init_template($p, 'users');
    my $lv = CATS::ListView->new(
        web => $p,
        name => 'users' . ($contest->is_practice ? '_practice' : ''),
        array_name => 'users',
        url => url_f('users'),
    );
    $t->param(title_suffix => res_str(526), users_submenu);

    if ($is_jury) {
        users_delete($p);
        CATS::User::new_save($p) if $p->{new_save};
        CATS::User::edit_save($p) if $p->{edit_save};

        CATS::User::save_attributes_jury($p) if $p->{save_attributes};
        CATS::User::set_tag(user_set => $p->{sel}, tag => $p->{tag_to_set}) if $p->{set_tag};
        CATS::User::gen_passwords(user_set => $p->{sel}, len => $p->{password_len}) if $p->{gen_passwords};

        if ($p->{send_message} && ($p->{message_text} // '') ne '') {
            my $contest_id = $is_root && $p->{send_all_contests} ? undef : $cid;
            if ($p->{send_all}) {
                CATS::User::send_broadcast(message => $p->{message_text}, contest_id => $contest_id);
                msg(1058);
            }
            else {
                my $count = CATS::User::send_message(
                    user_set => $p->{sel}, message => $p->{message_text}, contest_id => $contest_id);
                msg(1057, $count);
            }
            $dbh->commit;
        }
    }
    elsif ($user->{is_site_org}) {
        CATS::User::save_attributes_org($p) if $p->{save_attributes};
    }

    if ($is_jury || $user->{is_site_org}) {
        CATS::User::set_site(user_set => $p->{sel}, site_id => $p->{site_id}) if $p->{set_site};
        # Consider site_org without site_id as 'all sites organizer'.
        my ($site_cond, @site_param) = $is_jury || !$user->{site_id} ? ('') : (' AND S.id = ?', $user->{site_id});
        $t->param(sites => $dbh->selectall_arrayref(qq~
            SELECT S.id, S.name
            FROM sites S INNER JOIN contest_sites CS ON CS.site_id = S.id
            WHERE CS.contest_id = ?$site_cond
            ORDER BY S.name~, { Slice => {} },
            $cid, @site_param));
    }

    my $contact_types = $is_jury ? $dbh->selectall_arrayref(q~
        SELECT id, name FROM contact_types~, { Slice => {} }) : [];
    ($_->{sql} = $_->{name}) =~ tr/a-zA-Z0-9/_/c for @$contact_types;

    $lv->default_sort(0)->define_columns([
        ($is_jury ?
            { caption => res_str(616), order_by => 'login', width => '20%' } : ()),
        { caption => res_str(608), order_by => 'team_name', width => '30%', checkbox => $is_jury && '[name=sel]' },
        { caption => res_str(627), order_by => 'COALESCE(S.name, A.city)', width => '20%', col => 'Si' },
        { caption => res_str(689), order_by => 'affiliation', width => '5%', col => 'Af' },
        { caption => res_str(629), order_by => 'tag', width => '5%', col => 'Tg' },
        ($is_jury ? (
            map +{ caption => $_->{name}, order_by => "CT_$_->{sql}", width => '10%', col => "Ct$_->{sql}" },
            @$contact_types
        ) : ()),
        ($is_jury || $user->{is_site_org} ? (
            { caption => res_str(671), order_by => 'ip', width => '5%', col => 'Ip' },
            { caption => res_str(612), order_by => 'is_ooc', width => '1%', checkbox => '.is_ooc input' },
            { caption => res_str(613), order_by => 'is_remote', width => '1%', checkbox => '.is_remote input' },
            { caption => res_str(610), order_by => 'is_site_org', width => '1%', checkbox => '.is_site_org input' },
        ) : ()),
        ($is_jury ? (
            { caption => res_str(611), order_by => 'is_jury', width => '1%', checkbox => '.is_jury input' },
            { caption => res_str(614), order_by => 'is_hidden', width => '1%', checkbox => '.is_hidden input' },
        ) : ()),
        ($is_jury || $contest->{show_flags} ? (
            { caption => res_str(607), order_by => 'country', width => '5%', col => 'Fl' },
        ) : ()),
        ($is_jury || $contest->{show_all_results} ? (
            { caption => res_str(609), order_by => 'rating', width => '5%', col => 'Rt' },
        ) : ()),
        { caption => res_str(632), order_by => 'diff_time', width => '5%', col => 'Dt' },
    ]);

    return if !$is_jury && $p->{json} && $contest->is_practice;

    my @fields = qw(
        A.id A.country A.motto A.login A.team_name A.city A.last_ip A.affiliation
        CA.is_admin CA.is_jury CA.is_ooc CA.is_remote CA.is_hidden CA.is_site_org
        CA.is_virtual CA.diff_time CA.ext_time CA.tag
    );
    $lv->define_db_searches([ @fields, qw(
        A.affiliation_year A.capitan_name A.git_author_email A.git_author_name A.tz_offset
    ) ]);
    $lv->define_db_searches([ qw(A.sid) ]) if $is_root;
    $lv->define_subqueries({
        in_contest => { sq => q~EXISTS (
            SELECT 1 FROM contest_accounts CA1 WHERE CA1.account_id = A.id AND CA1.contest_id = ?)~,
            m => 1213, t => q~SELECT title FROM contests WHERE id = ?~
        },
        used_ip => { sq => q~EXISTS(
            SELECT 1 FROM reqs R INNER JOIN events E ON E.id = R.id
            WHERE R.account_id = A.id AND R.contest_id = C.id AND E.ip LIKE '%' || ? || '%')~,
        },
    });
    $lv->define_db_searches({ map { +"CT_$_->{sql}" => _contact_field_sql($_), } @$contact_types });
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

    my $check_site_id = !$is_jury && $user->{is_site_org} && $user->{site_id};
    my $ip_sql = do {
        my $s = $is_jury  && $lv->visible_cols->{Ip} || $user->{is_site_org} ? qq~
            SELECT E.ip FROM reqs R INNER JOIN events E ON E.id = R.id
            WHERE R.account_id = A.id AND R.contest_id = C.id
            ORDER BY R.submit_time DESC $db->{LIMIT} 1~ : 'NULL';
        $check_site_id ? qq~CASE WHEN CA.site_id = ? THEN ($s) ELSE NULL END~ : $s;
    };

    my @visible_contacts = grep $lv->visible_cols->{"Ct$_->{sql}"}, @$contact_types;
    $t->param(contacts => \@visible_contacts);
    my $contacts_sql = join '', map ', (' . _contact_field_sql($_) . ") AS CT_$_->{sql}", @visible_contacts;

    my $sql = sprintf qq~
        SELECT ($rating_sql) AS rating, ($ip_sql) AS ip, CA.id, $fields,
        CA.site_id, S.name AS site_name$contacts_sql
        FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id
            INNER JOIN contests C ON CA.contest_id = C.id
            LEFT JOIN sites S ON S.id = CA.site_id
        WHERE C.id = ?%s %s ~ . $lv->order_by,
        ($is_jury || $user->{is_site_org} && !$user->{site_id} ? '' :
        $user->{is_site_org} ? ' AND (CA.is_hidden = 0 OR CA.site_id = ?)' :
        ' AND CA.is_hidden = 0'),
        $lv->maybe_where_cond;

    my $sth = $dbh->prepare($sql);
    my @maybe_site_id = ($check_site_id ? $user->{site_id} : ());
    $sth->execute(@maybe_site_id, $cid, @maybe_site_id, $lv->where_params);

    my $fetch_record = sub {
        my (
            $accepted, $ip, $caid,
            $aid, $country_abbr, $motto, $login, $team_name, $city, $last_ip, $affiliation,
            $admin, $jury, $ooc, $remote, $hidden, $site_org, $virtual, $diff_time, $ext_time,
            $tag, $site_id, $site_name, @contacts
        ) = $_[0]->fetchrow_array
            or return ();
        my ($country, $flag) = CATS::Countries::get_flag($country_abbr);
        return (
            href_delete => url_f('users', delete_user => $caid),
            href_edit => url_f('users_edit', uid => $aid),
            href_stats => url_f('user_stats', uid => $aid),
            ($user->privs->{edit_sites} && $site_id ? (href_site => url_f('sites_edit', id => $site_id)) : ()),
            ($is_jury && $site_id ?
                (href_contest_site => url_f('contest_sites_edit', site_id => $site_id)) : ()),
            ($is_jury || $user->{is_site_org} ? (href_vdiff => url_f('user_vdiff', uid => $aid)) : ()),
            href_rank_table_filter => $is_jury ? url_f('rank_table', filter => $tag) : undef,
            href_contacts => url_f('user_contacts', uid => $aid, search => 'type_name=~type_name~'),

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
            affiliation => $affiliation,
            flag => $flag,
            accepted => $accepted,
            CATS::IP::linkify_ip($ip // $last_ip),
            last_ip_submission => $ip,
            admin => $admin,
            jury => $jury,
            hidden => $hidden,
            ooc => $ooc,
            remote => $remote,
            site_org => $site_org,
            editable_attrs =>
                ($is_jury || (!$user->{site_id} || $user->{site_id} == ($site_id // 0)) && $uid && $aid != $uid),
            virtual => $virtual,
            formatted_time => CATS::Time::format_diff_ext($diff_time, $ext_time, display_plus => 1),
            (map { +"CT_$_->{sql}" => shift @contacts } @visible_contacts),
         );
    };

    $lv->attach($fetch_record, $sth);
    $sth->finish;
}

sub users_all_settings_frame {
    my ($p) = @_;

    init_template($p, 'users_all_settings.html.tt');
    $is_root or return;

    my $lv = CATS::ListView->new(
        web => $p,
        name => 'users_all_settings',
        url => url_f('users_all_settings'),
        extra_settings => { selector => undef });

    $lv->default_sort(0)->define_columns([
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
        my $all_settings = $row->{settings} ? thaw($row->{settings}) : '';
        if ($all_settings && $selector) {
            for (split /\./, $selector) {
                $all_settings = $all_settings->{$_} or last;
            }
        }
        my $full = CATS::Settings::as_dump($all_settings, 0);
        my $short = length($full) < 120 ? $full : substr($full, 0, 120) . '...';
        (
            href_edit => url_f('users_edit', uid => $row->{id}),
            href_settings => url_f('user_settings', uid => $row->{id}),
            %$row,
            settings_short => $short,
            settings_full => $full,
        );
    };
    $lv->date_fields(qw(last_login));
    $lv->attach($fetch_record, $sth);
    $t->param(title_suffix => res_str(575), users_submenu);
}

1;
