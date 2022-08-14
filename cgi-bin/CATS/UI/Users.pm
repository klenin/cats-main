package CATS::UI::Users;

use strict;
use warnings;

use Encode;
use Storable;

use CATS::Awards;
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

my %user_fields = (password => 'password1', map { $_ => $_ } CATS::User::param_names);
my %ca_fields = (is_ooc => 1, is_hidden => 1);

sub users_import_frame {
    my ($p) = @_;
    init_template($p, 'users_import');
    $is_jury or return;
    my $contact_types = $dbh->selectall_hashref(q~
        SELECT id, name FROM contact_types~, 'name');
    $t->param(
        href_action => url_f('users_import'), title_suffix => res_str(564),
        CATS::User::users_submenu($p),
        contact_types => $contact_types, user_fields => { %user_fields, %ca_fields });
    $p->{go} or return;

    my @report;
    my ($header, @lines) = split "\r\n", $p->{user_list};
    my ($i, @fields_idx, @field_names_idx, @contact_types_idx, %ca_fields_idx) = (0);
    for my $h (split "\t", $header) {
        if (my $uf = $user_fields{$h}) {
            push @fields_idx, $i;
            push @field_names_idx, $uf;
        }
        elsif (my $ct = $contact_types->{$h}) {
            push @contact_types_idx, [ $i, $ct->{id} ];
        }
        elsif ($ca_fields{$h}) {
            $ca_fields_idx{$h} = $i;
        }
        else {
            push @report, "Unknown field: $h";
        }
        $i++;
    }

    my $count = 0;
    for my $line (@lines) {
        my @cols = split "\t", $line;
        my $u = CATS::User->new;
        @$u{@field_names_idx} = @cols[@fields_idx];
        $u->{login} or push @report, 'No login' and next;
        my ($user_id) = $dbh->selectrow_array(q~
            SELECT id FROM accounts WHERE login = ?~, undef,
            $u->{login});
        my $r =
            !$user_id ? eval {
                $u->{password1} = CATS::User::hash_password($u->{password1})
                    if $u->{password1};
                $u->insert($contest->{id}, commit => 0,
                    map { $_ => ($ca_fields_idx{$_} ? $cols[$ca_fields_idx{$_}] : 0) }
                        qw(is_ooc is_hidden));
                ++$count;
                'insert ok';
            } || $@ :
            $p->{update} ? eval {
                my $update;
                $update->{$_} = $u->{$_} for CATS::User::param_names;
                $update->{passwd} = CATS::User::hash_password($u->{password1})
                    if $u->{password1};
                $dbh->do(_u $sql->update('accounts', $update, { id => $user_id }));
                $u->{id} = $user_id;
                if (%ca_fields_idx) {
                    $dbh->do(_u $sql->update('contest_accounts',
                        { map { $_ => $cols[$ca_fields_idx{$_}] } keys %ca_fields_idx },
                        { contest_id => $cid, account_id => $user_id }));
                }
                ++$count;
                'update ok' ;
            } || $@
            : 'exists';
        my $contact_count = 0;
        for my $ct (@contact_types_idx) {
            my ($i, $ct_id) = @$ct;
            my $handle = $cols[$i] or next;
            my %pk = (account_id => $u->{id}, contact_type_id => $ct_id);
            if ($p->{update} && $user_id &&
                $dbh->selectrow_array(_u $sql->select('contacts', 'COUNT(*)', \%pk)) == 1
            ) {
                $contact_count += $dbh->do(_u $sql->update('contacts', { handle => $handle }, \%pk));
            }
            else {
                $contact_count += $dbh->do(_u $sql->insert('contacts', {
                    id => new_id,
                    account_id => $u->{id}, contact_type_id => $ct_id,
                    handle => $handle, is_actual => 1,
                }));
            }
        }
        push @report, "$u->{team_name} -- $r (contacts=$contact_count)";
    }

    $p->{do_import} ? $dbh->commit : $dbh->rollback;
    push @report, ($p->{do_import} ? 'Import' : 'Test') . " complete: $count";
    $t->param(complete => $count, report => join "\n", @report);
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
        $t->param(CATS::User::logins_maybe_added($p, [ 'users' ], $aids // []));
    }
    elsif ($p->{from_contest}) {
        CATS::User::copy_from_contest($p->{source_cid}, $p->{include_ooc});
    }
    elsif ($p->{from_group}) {
        CATS::User::copy_from_acc_group($p->{source_group_id}, $p->{include_admins});
    }
    $t->param(
        href_action => url_f('users_add_participants'),
        title_suffix => res_str(584),
        CATS::User::users_submenu($p),
        href_find_users => url_f('api_find_users', in_contest => 0),
        href_find_contests => url_f('api_find_contests'),
        href_find_acc_groups => url_f('api_find_acc_groups'),
    );
}

sub _contact_field_sql {
    qq~(
        SELECT CT.handle FROM contacts CT
        WHERE CT.account_id = A.id AND CT.contact_type_id = $_[0]->{id}
        ORDER BY is_actual DESC $db->{LIMIT} 1)~,
}

sub _add_to_group {
    my ($p) = @_;
    @{$p->{sel}} && $p->{to_group} or return;
    $dbh->selectrow_array(q~
        SELECT 1 FROM acc_group_contests
        WHERE contest_id = ? AND acc_group_id = ?~, undef,
        $cid, $p->{to_group}) or return;
    $user->{privs}->{manage_groups} || $dbh->selectrow_array(q~
        SELECT is_admin FROM acc_group_accounts
        WHERE account_id = ? AND acc_group_id = ?~, undef,
        $uid, $p->{to_group}) or return;
    my $added = CATS::AccGroups::add_accounts(
        CATS::User::ca_ids_to_accounts($p->{sel}), $p->{to_group}) // [];
    msg(1221, scalar @$added);
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
    $t->param(title_suffix => res_str(526), CATS::User::users_submenu($p));

    my $awards = $dbh->selectall_arrayref(_u $sql->select(
        'awards', 'id, name, color', { contest_id => $cid, ($is_jury ? () : (is_public => 1)) }, 'name'));
    my $awards_idx;
    $awards_idx->{$_->{id}} = $_ for @$awards;
    $t->param(awards => $awards, awards_idx => $awards_idx);

    if ($is_jury) {
        users_delete($p);
        CATS::User::new_save($p) if $p->{new_save};
        CATS::User::edit_save($p) if $p->{edit_save};

        CATS::User::save_attributes_jury($p) if $p->{save_attributes};
        CATS::User::set_tag(user_set => $p->{sel}, tag => $p->{tag_to_set}) if $p->{set_tag};
        CATS::User::gen_passwords(user_set => $p->{sel}, len => $p->{password_len}) if $p->{gen_passwords};

        CATS::Awards::add_award($p->{sel}, $p->{award}) if $p->{add_award};
        CATS::Awards::remove_award($p->{sel}, $p->{award}) if $p->{remove_award};

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
        _add_to_group($p) if $p->{add_to_group};
        my $is_admin_cond = $user->{privs}->{manage_groups} ? '' : ' AND AGA.is_admin = 1';
        $t->param(acc_groups => $dbh->selectall_arrayref(qq~
            SELECT AG.id, AG.name FROM acc_groups AG
            INNER JOIN acc_group_contests AGC ON AGC.acc_group_id = AG.id
            LEFT JOIN acc_group_accounts AGA ON AGA.acc_group_id = AG.id AND AGA.account_id = ?
            WHERE AGC.contest_id = ?$is_admin_cond
            ORDER BY AG.name~, { Slice => {} },
            $uid, $cid));

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
    return if $p->{json} && 0 < grep $p->{$_},
        qw(new_save edit_save save_attributes set_tag gen_passwords send_message set_site);

    my $contact_types = $is_jury ? $dbh->selectall_arrayref(q~
        SELECT id, name FROM contact_types~, { Slice => {} }) : [];
    ($_->{sql} = $_->{name}) =~ tr/a-zA-Z0-9/_/c for @$contact_types;

    $lv->default_sort(0)->define_columns([
        ($is_jury ?
            { caption => res_str(616), order_by => 'login', width => '20%', col => 'Lg' } : ()),
        { caption => res_str(608), order_by => 'team_name', width => '30%', checkbox => $is_jury && '[name=sel]' },
        { caption => res_str(627), order_by => 'COALESCE(S.name, A.city)', width => '20%', col => 'Si' },
        { caption => res_str(689), order_by => 'affiliation', width => '5%', col => 'Af' },
        { caption => res_str(629), order_by => 'tag', width => '5%', col => 'Tg' },
        ($is_jury ? (
            { caption => res_str(698), order_by => 'snippets', width => '5%', col => 'Sn' },
            map +{ caption => $_->{name},
                order_by => $lv->visible_cols->{"Ct$_->{sql}"} ? "CT_$_->{sql}" : _contact_field_sql($_),
                width => '10%', col => "Ct$_->{sql}" },
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
        { caption => res_str(694), order_by => 'groups', width => '10%', col => 'Gr' },
        ($is_jury || $contest->{show_flags} ? (
            { caption => res_str(607), order_by => 'country', width => '5%', col => 'Fl' },
        ) : ()),
        ($is_jury || $contest->{show_all_results} ? (
            { caption => res_str(609), order_by => 'rating', width => '5%', col => 'Rt' },
        ) : ()),
        { caption => res_str(814), order_by => 'awards', width => '10%', col => 'Aw' },
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
    $lv->default_searches([ qw(login team_name) ]);
    $lv->define_db_searches([ qw(A.sid) ]) if $is_root;
    $lv->define_db_searches({ groups_count => q~(
        SELECT COUNT(*)
        FROM acc_group_accounts AGA
        INNER JOIN acc_group_contests AGC ON AGC.acc_group_id = AGA.acc_group_id AND AGC.contest_id = C.id
        WHERE AGA.account_id = A.id)~
    });
    $lv->define_subqueries({
        in_contest => { sq => q~EXISTS (
            SELECT 1 FROM contest_accounts CA1 WHERE CA1.account_id = A.id AND CA1.contest_id = ?)~,
            m => 1213, t => q~SELECT title FROM contests WHERE id = ?~
        },
        used_ip => { sq => q~EXISTS(
            SELECT 1 FROM reqs R INNER JOIN events E ON E.id = R.id
            WHERE R.account_id = A.id AND R.contest_id = C.id AND E.ip LIKE '%' || ? || '%')~,
        },
        has_award => { sq => q~EXISTS(
            SELECT 1 FROM contest_account_awards CAA
            WHERE CAA.ca_id = CA.id AND CAA.award_id = ?)~,
        },
    });

    my $accepted_count_sql = qq~
        SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
        WHERE R.state = $cats::st_accepted AND R.account_id = A.id AND R.contest_id = C.id~ .
        ($is_jury ? '' : ' AND (R.submit_time < C.freeze_date OR C.defreeze_date < CURRENT_TIMESTAMP)');
    $lv->define_db_searches({ map { +"CT_$_->{sql}" => _contact_field_sql($_), } @$contact_types });
    $lv->define_db_searches({
        accepted => "($accepted_count_sql)",
        'CA.id' => 'CA.id',
        is_judge => q~
            CASE WHEN EXISTS (SELECT * FROM judges J WHERE J.account_id = A.id) THEN 1 ELSE 0 END~,
        site_name => 'S.name',
        site_id => 'COALESCE(CA.site_id, 0)',
    });

    my $view_snippets;
    if ($is_jury) {
        $view_snippets = $dbh->selectall_arrayref(q~
            SELECT JVS.*, CP.code FROM jury_view_snippets JVS
            INNER JOIN contest_problems CP ON CP.problem_id = JVS.problem_id AND CP.contest_id = ?
            WHERE JVS.ca_id = ?~, { Slice => {} },
            $cid, $user->{ca_id});
        $lv->define_db_searches({
            map { +"snip_$_->{code}_$_->{snippet_name}" => qq~(
                SELECT text FROM snippets S
                WHERE S.contest_id = CA.contest_id AND S.problem_id = $_->{problem_id} AND
                    S.account_id = A.id AND S.name = '$_->{snippet_name}')~ }
            grep $_->{snippet_name} =~ /^[a-zA-Z0-9_]+$/, @$view_snippets
        });
    }

    $lv->define_enums({ site_id => { 'my' => $user->{site_id} } }) if $user->{site_id};
    $lv->define_enums({ has_award => { map { $_->{name} => $_->{id} } @$awards } });

    CATS::AccGroups::subquery($lv, 'A.id');
    CATS::AccGroups::enum($lv) if $is_jury;

    my $fields = join ', ', @fields;
    my $rating_sql = $lv->visible_cols->{Rt} ? $accepted_count_sql : 'NULL';

    my $check_site_id = !$is_jury && $user->{is_site_org} && $user->{site_id};
    my $ip_sql = do {
        my $s = $is_jury  && $lv->visible_cols->{Ip} || $user->{is_site_org} ? qq~
            SELECT E.ip FROM reqs R INNER JOIN events E ON E.id = R.id
            WHERE R.account_id = A.id AND R.contest_id = C.id
            ORDER BY R.submit_time DESC $db->{LIMIT} 1~ : 'NULL';
        $check_site_id ? qq~CASE WHEN CA.site_id = ? THEN ($s) ELSE NULL END~ : $s;
    };

    my $snippet_single_sql = qq~
        SELECT CAST(SUBSTRING(S.text FROM 1 FOR 200) AS VARCHAR(200)) AS text FROM snippets S
        INNER JOIN jury_view_snippets JVS ON
            JVS.ca_id = $user->{ca_id} AND JVS.snippet_name = S.name AND JVS.problem_id = S.problem_id
        WHERE S.contest_id = CA.contest_id AND S.account_id = CA.account_id~;
    my $snippets_sql =
        !$lv->visible_cols->{Sn} || !$view_snippets ? 'NULL' :
        @$view_snippets == 1 ? $snippet_single_sql : # Optimization & allow for correct sorting.
        qq~
            SELECT LIST(text, ' | ') FROM ($snippet_single_sql ORDER BY S.name)~;

    my @visible_contacts = grep $lv->visible_cols->{"Ct$_->{sql}"}, @$contact_types;
    $t->param(contacts => \@visible_contacts);
    my $contacts_sql = join '', map ', (' . _contact_field_sql($_) . ") AS CT_$_->{sql}", @visible_contacts;
    my $groups_sql = !$lv->visible_cols->{Gr} ? 'NULL' : qq~
        SELECT LIST(AG.name, ' ') FROM acc_groups AG
        INNER JOIN acc_group_accounts AGA ON AGA.acc_group_id = AG.id
        INNER JOIN acc_group_contests AGC ON AGC.acc_group_id = AG.id
        WHERE AGC.contest_id = CA.contest_id AND AGA.account_id = A.id
        $db->{LIMIT} 5~;

    my $awards_public_cond = $is_jury ? '' : ' AND AW.is_public = 1';
    my $awards_sql = !$lv->visible_cols->{Aw} ? 'NULL' : qq~
        SELECT LIST(CAA.award_id, ' ') FROM contest_account_awards CAA
        INNER JOIN awards AW ON AW.id = CAA.award_id
        WHERE CAA.ca_id = CA.id$awards_public_cond $db->{LIMIT} 5~;
    my $sql = sprintf qq~
        SELECT
            ($rating_sql) AS rating, ($ip_sql) AS ip, CA.id, $fields,
            CA.site_id, S.name AS site_name, ($groups_sql) AS groups,
            ($snippets_sql) AS snippets,
            ($awards_sql) AS awards$contacts_sql
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
            $tag, $site_id, $site_name, $groups, $snippets, $awards, @contacts
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
            snippets => $snippets,
            groups => [ split /\s+/, $groups // '' ],
            awards => [ split /\s+/, $awards // '' ],
            (map { +"CT_$_->{sql}" => shift @contacts } @visible_contacts),
         );
    };

    $lv->attach($fetch_record, $sth);
    $sth->finish;
}

sub users_all_settings_frame {
    my ($p) = @_;

    init_template($p, 'users_all_settings');
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
    $lv->default_searches([ qw(login team_name) ]);

    my $sth = $dbh->prepare(q~
        SELECT A.id, A.login, A.team_name, A.last_login, A.settings
        FROM accounts A
        INNER JOIN contest_accounts CA ON A.id = CA.account_id
        WHERE CA.contest_id = ?~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $selector = $lv->settings->{selector};
    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        my $all_settings = $row->{settings} && eval { Storable::thaw($row->{settings}) } || '';
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
    $t->param(title_suffix => res_str(575), CATS::User::users_submenu($p));
}

1;
