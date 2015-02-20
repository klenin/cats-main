package CATS::UI::Users;

use strict;
use warnings;

use Data::Dumper;
use CATS::Web qw(param url_param);
use CATS::DB;
use CATS::Constants;
use CATS::Misc qw(
    $t $is_jury $is_root $is_team $sid $cid $uid $contest $is_virtual $settings
    init_template init_listview_template msg res_str url_f auto_ext
    order_by define_columns attach_listview);
use CATS::Utils qw(url_function);
use CATS::Web qw(redirect);
use CATS::Data qw(:all);
use CATS::User;
use CATS::RankTable;
use CATS::Countries;

# Admin adds new user to current contest
sub users_new_save
{
    $is_jury or return;
    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->insert($cid) or return;
}

sub users_edit_frame
{
    init_template('users_edit.html.tt');

    my $id = url_param('edit') or return;
    my $u = CATS::User->new->load($id, [ 'locked' ]) or return;
    $t->param(
        %$u, id => $id, countries => \@CATS::Countries::countries, is_root => $is_root,
        href_action => url_f('users'),
        href_impersonate => url_f('users', impersonate => $id));
}

sub users_edit_save
{
    my $u = CATS::User->new->parse_params;
    # Simple $is_jury check is insufficient since jury member
    # can add any team to his contest.
    my $set_password = param_on('set_password') && $is_root;
    my $id = param('id');

    $u->validate_params(
        validate_password => $set_password, id => $id,
        # Need at least $is_jury in all official contests where $u participated.
        allow_official_rename => $is_root)
        or return;

    $u->{passwd} = $u->{password1} if $set_password;
    delete @$u{qw(password1 password2)};
    $u->{locked} = param('locked') ? 1 : 0 if $is_root;
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
    $u->insert(undef, save_settings => 1) or return;
    $t->param(successfully_registred => 1);
}

sub settings_save
{
    my $u = CATS::User->new->parse_params;
    my $set_password = param_on('set_password');

    $u->validate_params(validate_password => $set_password, id => $uid) or return;

    $u->{passwd} = $u->{password1} if $set_password;
    delete @$u{qw(password1 password2)};
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

sub settings_frame
{
    init_template('settings.html.tt');
    $settings = {} if defined param('clear') && $is_team;
    settings_save if defined param('edit_save') && $is_team;

    $uid or return;
    my $u = CATS::User->new->load($uid) or return;
    $t->param(
        countries => \@CATS::Countries::countries, href_action => url_f('users'),
        title_suffix => res_str(518), %$u);
    if ($is_jury) {
        $t->param(langs => [
            map { href => url_f('settings', lang => $_), name => $_ }, @cats::langs
        ]);
    }
    if ($is_root) {
        # Data::Dumper escapes UTF-8 characters into \x{...} sequences.
        # Work around by dumping encoded strings, then decoding the result.
        my $d = Data::Dumper->new([ apply_rec($settings, \&Encode::encode_utf8) ]);
        $d->Quotekeys(0);
        $d->Sortkeys(1);
        $t->param(settings => Encode::decode_utf8($d->Dump));
    }
}

sub users_send_message
{
    my %p = @_;
    $p{'message'} ne '' or return;
    my $s = $dbh->prepare(qq~
        INSERT INTO messages (id, send_time, text, account_id, received)
            VALUES (?, CURRENT_TIMESTAMP, ?, ?, 0)~
    );
    for (split ':', $p{'user_set'})
    {
        next unless param_on("msg$_");
        $s->bind_param(1, new_id);
        $s->bind_param(2, $p{'message'}, { ora_type => 113 });
        $s->bind_param(3, $_);
        $s->execute;
    }
    $s->finish;
}

sub users_set_tag
{
    my %p = @_;
    ($p{'tag'} || '') ne '' or return;
    my $s = $dbh->prepare(qq~
        UPDATE contest_accounts SET tag = ? WHERE id = ?~);
    for (split ':', $p{user_set})
    {
        param_on("msg$_") or next;
        $s->bind_param(1, $p{tag}, { ora_type => 113 });
        $s->bind_param(2, $_);
        $s->execute;
    }
    $s->finish;
    $dbh->commit;
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
    my ($aid, $srole) = $dbh->selectrow_array(qq~
        SELECT A.id, A.srole FROM accounts A
            INNER JOIN contest_accounts CA ON A.id = CA.account_id
            WHERE CA.id = ?~, {},
        $caid);

    if ($srole)
    {
        $dbh->do(qq~DELETE FROM contest_accounts WHERE id=?~, {}, $caid);
        $dbh->commit;

        unless ($dbh->selectrow_array(qq~
            SELECT COUNT(*) FROM contest_accounts WHERE account_id=?~, {}, $aid))
        {
            $dbh->do(qq~DELETE FROM accounts WHERE id=?~, {}, $aid);
            $dbh->commit;
        }
    }
}

sub users_save_attributes
{
    for (split(':', param('user_set')))
    {
        my $jury = param_on("jury$_");
        my $ooc = param_on("ooc$_");
        my $remote = param_on("remote$_");
        my $hidden = param_on("hidden$_");

        # Forbid removing is_jury privilege from an admin.
        my ($srole) = $dbh->selectrow_array(qq~
            SELECT A.srole FROM accounts A
                INNER JOIN contest_accounts CA ON A.id = CA.account_id
                WHERE CA.id = ?~, {},
            $_
        );
        $jury = 1 if !$srole;

        # Security: Forbid changing of user parameters in other contests.
        $dbh->do(qq~
            UPDATE contest_accounts
                SET is_jury = ?, is_hidden = ?, is_remote = ?, is_ooc = ?
                WHERE id = ? AND contest_id = ?~, {},
            $jury, $hidden, $remote, $ooc, $_, $cid
        );
    }
    $dbh->commit;
    CATS::RankTable::remove_cache($cid);
}

sub users_impersonate
{
    my $new_user_id = param('impersonate') or return;
    $dbh->selectrow_array(q~
        SELECT 1 FROM accounts WHERE id = ?~, undef, $new_user_id) or return;
    $dbh->do(q~
        UPDATE accounts SET sid = NULL WHERE id = ?~, undef, $uid);
    $dbh->do(q~
        UPDATE accounts SET last_ip = ?, sid = ? WHERE id = ?~, undef,
        CATS::IP::get_ip(), $sid, $new_user_id);
    $dbh->commit;
    redirect(url_function('contests', sid => $sid));
}

sub users_frame
{
    if ($is_jury)
    {
        users_delete if defined url_param('delete');
        return CATS::User::new_frame if defined url_param('new');
        return users_edit_frame if defined url_param('edit');
    }
    return users_impersonate if defined url_param('impersonate') && $is_root;

    init_listview_template(
        'users' . ($contest->is_practice ? '_practice' : ''),
        'users', auto_ext('users'));

    $t->param(messages => $is_jury, title_suffix => res_str(526));

    if ($is_jury)
    {
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
            }
            else
            {
                users_send_message(user_set => param('user_set'), message => param('message_text'));
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
        push @cols,
            (
              { caption => res_str(611), order_by => 'is_jury', width => '5%' },
              { caption => res_str(612), order_by => 'is_ooc', width => '5%' },
              { caption => res_str(613), order_by => 'is_remote', width => '5%' },
              { caption => res_str(614), order_by => 'is_hidden', width => '5%' } );
    }

    push @cols, (
        { caption => res_str(607), order_by => 'country', width => '5%' },
        { caption => res_str(609), order_by => 'rating', width => '5%' },
        { caption => res_str(622), order_by => 'is_virtual', width => '5%' } );

    define_columns(url_f('users'), $is_jury ? 3 : 2, 1, \@cols);

    return if !$is_jury && param('json') && $contest->is_practice;

    my $fields =
        'A.id, CA.id, A.country, A.login, A.team_name, A.city, ' .
        'CA.is_jury, CA.is_ooc, CA.is_remote, CA.is_hidden, CA.is_virtual, A.motto, CA.tag';
    my $sql = sprintf qq~
        SELECT $fields, COUNT(DISTINCT R.problem_id) as rating
        FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id
            INNER JOIN contests C ON CA.contest_id = C.id
            LEFT JOIN reqs R ON
                R.state = $cats::st_accepted AND R.account_id = A.id AND R.contest_id = C.id%s
        WHERE C.id = ?%s GROUP BY $fields ~ . order_by,
        ($is_jury ? ('', '') : (
            ' AND (R.submit_time < C.freeze_date OR C.defreeze_date < CURRENT_TIMESTAMP)',
            ' AND CA.is_hidden = 0'));

    my $c = $dbh->prepare($sql);
    $c->execute($cid);

    my $fetch_record = sub($)
    {
        my (
            $aid, $caid, $country_abbr, $login, $team_name, $city, $jury,
            $ooc, $remote, $hidden, $virtual, $motto, $tag, $accepted
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
            editable => $is_jury,
            messages => $is_jury,
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
         );
    };

    attach_listview(url_f('users'), $fetch_record, $c);

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
    my $hidden_cond = $is_root ? '' :
        'AND (CA.is_hidden = 0 OR CA.is_hidden IS NULL) AND C.defreeze_date < CURRENT_TIMESTAMP';
    my $u = $dbh->selectrow_hashref(q~
        SELECT A.*, last_login AS last_login_date
        FROM accounts A WHERE A.id = ?~, { Slice => {} }, $uid) or return;
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
            CA.account_id = ? AND C.ctype = 0 AND C.is_hidden = 0 $hidden_cond
        ORDER BY C.start_date + CA.diff_time DESC~,
        { Slice => {} }, $uid);
    my $pr = sub { url_f(
        'console', uf => $uid, i_value => -1, se => 'user_stats', show_results => 1, search => $_[0], rows => 30
    ) };
    for (@$contests) {
        $_->{href_send_message} = url_f('send_message_box', caid => $_->{caid}) if $is_root;
        $_->{href_problems} = url_function('problems', sid => $sid, cid => $_->{id});
    }
    $t->param(
        %$u, contests => $contests, is_root => $is_root,
        CATS::IP::linkify_ip(CATS::IP::filter_ip $u->{last_ip}),
        ($is_jury ? (href_edit => url_f('users', edit => $uid)) : ()),
        href_all_problems => $pr->(''),
        href_solved_problems => $pr->('accepted=1'),
        title_suffix => $u->{team_name},
    );
}

1;
