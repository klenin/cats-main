#!/usr/bin/perl
package main;

use strict;
use warnings;
use encoding 'utf8', STDIN => undef;

use Encode;

use Data::Dumper;
use Storable ();
use Time::HiRes;

our $cats_lib_dir;
BEGIN {
    $cats_lib_dir = $ENV{CATS_DIR} || '.';
    $cats_lib_dir =~ s/\/$//;
    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 1;
    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT_OK = qw(
        handler
        );
    our %EXPORT_TAGS = (all => [@EXPORT_OK]);
}
use lib $cats_lib_dir;


use CATS::Web qw(param url_param save_uploaded_file redirect upload_source init_request get_return_code);
use CATS::DB;
use CATS::Constants;
use CATS::BinaryFile;
use CATS::DevEnv;
use CATS::Misc qw(:all);
use CATS::Utils qw(coalesce escape_html url_function state_to_display param_on);
use CATS::Data qw(:all);
use CATS::IP;
use CATS::Problem;
use CATS::Problem::Text;
use CATS::RankTable;
use CATS::StaticPages;
use CATS::TeX::Lite;
use CATS::Testset;
use CATS::Contest::Results;
use CATS::User;
use CATS::Console;
use CATS::RunDetails;
use CATS::UI::Prizes;
use CATS::UI::Messages;
use CATS::UI::Stats;
use CATS::UI::Judges;
use CATS::UI::Compilers;
use CATS::UI::Keywords;
use CATS::UI::Problems;

sub make_sid {
    my @ch = ('A'..'Z', 'a'..'z', '0'..'9');
    join '', map { $ch[rand @ch] } 1..30;
}


sub login_frame
{
    my $json = param('json');
    init_template(auto_ext('login', $json));
    $t->param(href_login => url_function('login'));
    msg(1004) if param('logout');

    my $login = param('login');
    if (!$login) {
        $t->param(message => 'No login') if $json;
        return;
    }
    $t->param(login => Encode::decode_utf8($login));
    my $passwd = param('passwd');

    my ($aid, $passwd2, $locked) = $dbh->selectrow_array(qq~
        SELECT id, passwd, locked FROM accounts WHERE login = ?~, undef, $login);

    $aid && $passwd2 eq $passwd or return msg(1040);
    !$locked or return msg(1041);

    my $last_ip = CATS::IP::get_ip();

    my $cid = url_param('cid');
    for (1..20) {
        $sid = make_sid;

        $dbh->do(qq~
            UPDATE accounts SET sid = ?, last_login = CURRENT_TIMESTAMP, last_ip = ?
                WHERE id = ?~,
            {}, $sid, $last_ip, $aid
        ) or next;
        $dbh->commit;

        if ($json) {
            $contest->load($cid, ['id']);
            $t->param(sid => $sid, cid => $contest->{id});
            return;
        }
        $t = undef;
        return redirect(url_function('contests', sid => $sid, cid => $cid));
    }
    die 'Can not generate sid';
}


sub logout_frame
{
    $cid = '';
    $sid = '';
    if ($uid) {
        $dbh->do(qq~UPDATE accounts SET sid = NULL WHERE id = ?~, {}, $uid);
        $dbh->commit;
    }
    if (param('json')) {
        init_template(auto_ext('logout'));
        0;
    }
    else {
       redirect(url_function('login', logout => 1));
    }
}


sub contests_new_frame
{
    init_template('contests_new.html.tt');

    my $date = $dbh->selectrow_array(q~SELECT CURRENT_TIMESTAMP FROM RDB$DATABASE~);
    $date =~ s/\s*$//;
    $t->param(
        start_date => $date, freeze_date => $date,
        finish_date => $date, open_date => $date,
        can_edit => 1,
        is_hidden => !$is_root,
        show_all_results => 1,
        href_action => url_f('contests')
    );
}


sub contest_checkbox_params()
{qw(
    free_registration run_all_tests
    show_all_tests show_test_resources show_checker_comment show_all_results
    is_official show_packages local_only is_hidden
)}


sub contest_string_params()
{qw(
    contest_name start_date freeze_date finish_date open_date rules max_reqs
)}


sub get_contest_html_params
{
    my $p = {};

    $p->{$_} = scalar param($_) for contest_string_params();
    $p->{$_} = param_on($_) for contest_checkbox_params();

    $p->{contest_name} ne '' && length $p->{contest_name} < 100
        or return msg(27);

    $p;
}


sub register_contest_account
{
    my %p = @_;
    $p{$_} ||= 0 for (qw(is_jury is_pop is_hidden is_virtual diff_time));
    $p{$_} ||= 1 for (qw(is_ooc is_remote));
    $p{id} = new_id;
    my ($f, $v) = (join(', ', keys %p), join(',', map '?', keys %p));
    $dbh->do(qq~
        INSERT INTO contest_accounts ($f) VALUES ($v)~, undef,
        values %p);
    my $p = cats_dir() . "./rank_cache/$p{contest_id}#";
    unlink <$p*>;
}


sub contests_new_save
{
    my $p = get_contest_html_params() or return;

    my $cid = new_id;
    # free_registration => closed
    $p->{free_registration} = !$p->{free_registration};
    $dbh->do(qq~
        INSERT INTO contests (
            id, title, start_date, freeze_date, finish_date, defreeze_date, rules, max_reqs,
            ctype,
            closed, run_all_tests, show_all_tests,
            show_test_resources, show_checker_comment, show_all_results,
            is_official, show_packages, local_only, is_hidden, show_frozen_reqs
        ) VALUES(
            ?, ?, ?, ?, ?, ?, ?, ?,
            0,
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)~,
        {},
        $cid, @$p{contest_string_params()},
        @$p{contest_checkbox_params()}
    );

    # Automatically register all admins as jury.
    my $root_accounts = $dbh->selectcol_arrayref(qq~
        SELECT id FROM accounts WHERE srole = ?~, undef, $cats::srole_root);
    push @$root_accounts, $uid unless $is_root; # User with contests_creator role.
    for (@$root_accounts)
    {
        register_contest_account(
            contest_id => $cid, account_id => $_,
            is_jury => 1, is_pop => 1, is_hidden => 1);
    }
    $dbh->commit;
}


sub try_contest_params_frame
{
    my $id = url_param('params') or return;

    init_template('contest_params.html.tt');

    my $p = $dbh->selectrow_hashref(qq~
        SELECT
            title AS contest_name,
            start_date,
            freeze_date,
            finish_date,
            defreeze_date AS open_date,
            1 - closed AS free_registration,
            run_all_tests, show_all_tests, show_test_resources, show_checker_comment,
            show_all_results, is_official, show_packages, local_only, rules, is_hidden, max_reqs
        FROM contests WHERE id = ?~, { Slice => {} },
        $id
    ) or return;
    $t->param(
        id => $id, %$p,
        href_action => url_f('contests'),
        can_edit => (get_registered_contestant(fields => 'is_jury', contest_id => $id) ? 1 : 0),
    );

    1;
}


sub contests_edit_save
{
    my $edit_cid = param('id');

    my $p = get_contest_html_params() or return;

    # free_registration => closed
    $p->{free_registration} = !$p->{free_registration};
    $dbh->do(qq~
        UPDATE contests SET
            title=?, start_date=?, freeze_date=?,
            finish_date=?, defreeze_date=?, rules=?, max_reqs=?,
            closed=?, run_all_tests=?, show_all_tests=?,
            show_test_resources=?, show_checker_comment=?, show_all_results=?,
            is_official=?, show_packages=?,
            local_only=?, is_hidden=?, show_frozen_reqs=0
        WHERE id=?~,
        {},
        @$p{contest_string_params()},
        @$p{contest_checkbox_params()},
        $edit_cid
    );
    $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(cid => $edit_cid, all => 1);
    CATS::RankTable::remove_cache($edit_cid);
    # Change page title immediately if the current contest is renamed.
    if ($edit_cid == $cid) {
        $contest->{title} = Encode::decode_utf8($p->{contest_name});
    }
}


sub contest_online_registration
{
    !get_registered_contestant(contest_id => $cid)
        or return msg(111);

    if ($is_root)
    {
        register_contest_account(
            contest_id => $cid, account_id => $uid,
            is_jury => 1, is_pop => 1, is_hidden => 1);
    }
    else
    {
        $contest->{time_since_finish} <= 0 or return msg(108);
        !$contest->{closed} or return msg(105);
        register_contest_account(contest_id => $cid, account_id => $uid);
    }
    $dbh->commit;
}


sub contest_virtual_registration
{
    my ($registered, $is_virtual, $is_remote) = get_registered_contestant(
         fields => '1, is_virtual, is_remote', contest_id => $cid);

    !$registered || $is_virtual
        or return msg(114);

    $contest->{time_since_start} >= 0
        or return msg(109);

    # In official contests, virtual participation is allowed only after the finish.
    $contest->{time_since_finish} >= 0 || !$contest->{is_official}
        or return msg(122);

    !$contest->{closed}
        or return msg(105);

    # Repeat virtual registration removes old results.
    if ($registered)
    {
        $dbh->do(qq~
            DELETE FROM reqs WHERE account_id = ? AND contest_id = ?~, undef,
            $uid, $cid);
        $dbh->do(qq~
            DELETE FROM contest_accounts WHERE account_id = ? AND contest_id = ?~, undef,
            $uid, $cid);
        $dbh->commit;
        msg(113);
    }

    register_contest_account(
        contest_id => $cid, account_id => $uid,
        is_virtual => 1, is_remote => $is_remote,
        diff_time => $contest->{time_since_start});
    $dbh->commit;
}


sub contests_select_current
{
    defined $uid or return;

    my ($registered, $is_virtual, $is_jury) = get_registered_contestant(
        fields => '1, is_virtual, is_jury', contest_id => $cid
    );
    return if $is_jury;

    $t->param(selected_contest_title => $contest->{title});

    if ($contest->{time_since_finish} > 0)
    {
        msg(115);
    }
    elsif (!$registered)
    {
        msg(116);
    }
}

sub date_to_iso {
    $_[0] =~ /^\s*(\d+)\.(\d+)\.(\d+)\s+(\d+):(\d+)\s*$/;
    "$3$2$1T$4${5}00";
}

sub common_contests_view ($)
{
    my ($c) = @_;
    return (
       id => $c->{id},
       contest_name => $c->{title},
       start_date => $c->{start_date},
       start_date_iso => date_to_iso($c->{start_date}),
       finish_date => $c->{finish_date},
       finish_date_iso => date_to_iso($c->{finish_date}),
       registration_denied => $c->{closed},
       selected => $c->{id} == $cid,
       is_official => $c->{is_official},
       show_points => $c->{rules},
       href_contest => url_function('contests', sid => $sid, set_contest => 1, cid => $c->{id}),
       href_params => url_f('contests', params => $c->{id}),
    );
}

sub contest_fields ()
{
    # HACK: starting page is a contests list, displayed very frequently.
    # In the absense of a filter, select only the first page + 1 record.
    # my $s = $settings->{$listview_name};
    # (($s->{page} || 0) == 0 && !$s->{search} ? 'FIRST ' . ($s->{rows} + 1) : '') .
    q~c.ctype, c.id, c.title,
    c.start_date, c.finish_date, c.closed, c.is_official, c.rules~
}


sub contests_submenu_filter
{
    my $f = $settings->{contests}->{filter} || '';
    {
        all => '',
        official => 'AND C.is_official = 1 ',
        unfinished => 'AND CURRENT_TIMESTAMP <= finish_date ',
        current => 'AND CURRENT_TIMESTAMP BETWEEN start_date AND finish_date ',
        json => q~
            AND EXISTS (
                SELECT 1 FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
                WHERE CP.contest_id = C.id AND P.json_data IS NOT NULL)~,
    }->{$f} || '';
}


sub authenticated_contests_view ()
{
    my $cf = contest_fields();
    my $has_problem = param('has_problem');
    my $has_problem_orig = $has_problem ?
        '(SELECT 1 FROM problems P WHERE P.contest_id = C.id AND P.id = ?)' : '0';
    my $sth = $dbh->prepare(qq~
        SELECT
            $cf, CA.is_virtual, CA.is_jury, CA.id AS registered, C.is_hidden,
            $has_problem_orig AS has_orig
        FROM contests C LEFT JOIN
            contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        WHERE
            (CA.account_id IS NOT NULL OR COALESCE(C.is_hidden, 0) = 0) ~ .
            ($has_problem ? q~AND EXISTS (
                SELECT 1 FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.problem_id = ?) ~ : contests_submenu_filter()) .
            order_by);
    $sth->execute($has_problem ? ($has_problem, $uid, $has_problem) : ($uid));

    my $fetch_contest = sub($)
    {
        my $c = $_[0]->fetchrow_hashref or return;
        return (
            common_contests_view($c),
            is_hidden => $c->{is_hidden},
            authorized => 1,
            editable => $c->{is_jury},
            deletable => $is_root,
            registered_online => $c->{registered} && !$c->{is_virtual},
            registered_virtual => $c->{registered} && $c->{is_virtual},
            href_delete => url_f('contests', delete => $c->{id}),
            has_orig => $c->{has_orig},
        );
    };
    return ($fetch_contest, $sth);
}


sub anonymous_contests_view ()
{
    my $cf = contest_fields();
    my $sth = $dbh->prepare(qq~
        SELECT $cf FROM contests C WHERE COALESCE(C.is_hidden, 0) = 0 ~ .
        contests_submenu_filter() . order_by
    );
    $sth->execute;

    my $fetch_contest = sub($)
    {
        my $c = $_[0]->fetchrow_hashref or return;
        return common_contests_view($c);
    };
    return ($fetch_contest, $sth);
}


sub contests_frame
{
    if (defined param('summary_rank'))
    {
        my @clist = param('contests_selection');
        return redirect(url_f('rank_table', clist => join ',', @clist));
    }

    return contests_new_frame
        if defined url_param('new') && $CATS::Misc::can_create_contests;

    try_contest_params_frame and return;

    my $ical = param('ical');
    my $json = param('json');
    return if $ical && $json;
    init_listview_template('contests', 'contests',
        'contests.' .  ($ical ? 'ics' : $json ? 'json' : 'html') . '.tt');

    CATS::UI::Prizes::contest_group_auto_new if defined param('create_group') && $is_root;

    if (defined url_param('delete') && $is_root) {
        my $cid = url_param('delete');
        $dbh->do(qq~DELETE FROM contests WHERE id = ?~, {}, $cid);
        $dbh->commit;
        msg(1037);
    }

    contests_new_save if defined param('new_save') && $CATS::Misc::can_create_contests;

    contests_edit_save
        if defined param('edit_save') &&
            get_registered_contestant(fields => 'is_jury', contest_id => param('id'));

    contest_online_registration if defined param('online_registration');

    my $vr = param('virtual_registration');
    contest_virtual_registration if defined $vr && $vr;

    contests_select_current if defined url_param('set_contest');

    define_columns(url_f('contests'), 1, 1, [
        { caption => res_str(601), order_by => '1 DESC, 2', width => '40%' },
        { caption => res_str(600), order_by => '1 DESC, 4', width => '15%' },
        { caption => res_str(631), order_by => '1 DESC, 5', width => '15%' },
        { caption => res_str(630), order_by => '1 DESC, 8', width => '30%' } ]);

    $_ = coalesce(param('filter'), $_, 'unfinished') for $settings->{contests}->{filter};

    attach_listview(url_f('contests'),
        defined $uid ? authenticated_contests_view : anonymous_contests_view,
        ($uid ? () : { page_params => { filter => $settings->{contests}->{filter} } }));

    my $submenu = [
        map({
            href => url_f('contests', page => 0, filter => $_->{n}),
            item => res_str($_->{i}),
            selected => $settings->{contests}->{filter} eq $_->{n},
        }, { n => 'all', i => 558 }, { n => 'official', i => 559 }, { n => 'unfinished', i => 560 }),
        ($CATS::Misc::can_create_contests ?
            { href => url_f('contests', new => 1), item => res_str(537) } : ()),
        { href => url_f('contests',
            ical => 1, rows => 50, filter => $settings->{contests}->{filter}), item => res_str(562) },
    ];
    $t->param(
        submenu => $submenu,
        authorized => defined $uid,
        href_contests => url_f('contests'),
        is_root => $is_root,
        is_registered => defined $uid && get_registered_contestant(contest_id => $cid) || 0,
    );
}


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
        %$u, id => $id, countries => \@cats::countries, is_root => $is_root,
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
    for my $line (split "\r\n", decode_utf8(param('user_list'))) {
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

    $t->param(countries => [ @cats::countries ], href_login => url_f('login'));

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
        countries => \@cats::countries, href_action => url_f('users'),
        title_suffix => res_str(518), %$u);
    if ($is_jury) {
        $t->param(langs => [
            map { href => url_f('settings', lang => $_), name => $_ }, @cats::langs
        ]);
    }
    if ($is_root) {
        # Data::Dumper escapes UTF-8 characters into \x{...} sequences.
        # Work around by dumping encoded strings, then decoding the result.
        my $d = Data::Dumper->new([ apply_rec($settings, \&encode_utf8) ]);
        $d->Quotekeys(0);
        $d->Sortkeys(1);
        $t->param(settings => decode_utf8($d->Dump));
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

        # нельзя снять is_jury у администратора
        my ($srole) = $dbh->selectrow_array(qq~
            SELECT A.srole FROM accounts A
                INNER JOIN contest_accounts CA ON A.id = CA.account_id
                WHERE CA.id = ?~, {},
            $_
        );
        $jury = 1 if !$srole;

        # security: запрещаем менять параметры пользователей в других трнирах
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
            $aid, $caid, $country_abb, $login, $team_name, $city, $jury,
            $ooc, $remote, $hidden, $virtual, $motto, $tag, $accepted
        ) = $_[0]->fetchrow_array
            or return ();
        my ($country, $flag) = get_flag($country_abb);
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


sub import_sources_frame
{
    init_listview_template('import_sources', 'import_sources', 'import_sources.html.tt');
    define_columns(url_f('import_sources'), 0, 0, [
        { caption => res_str(625), order_by => '2', width => '30%' },
        { caption => res_str(642), order_by => '3', width => '30%' },
        { caption => res_str(641), order_by => '4', width => '30%' },
        { caption => res_str(643), order_by => '5', width => '10%' },
    ]);

    my $c = $dbh->prepare(qq~
        SELECT ps.id, ps.guid, ps.stype, de.code,
            (SELECT COUNT(*) FROM problem_sources_import psi WHERE ps.guid = psi.guid) AS ref_count,
            ps.fname, ps.problem_id, p.title, p.contest_id
            FROM problem_sources ps INNER JOIN default_de de ON de.id = ps.de_id
            INNER JOIN problems p ON p.id = ps.problem_id
            WHERE ps.guid IS NOT NULL ~.order_by);
    $c->execute;

    my $fetch_record = sub($)
    {
        my $f = $_[0]->fetchrow_hashref or return ();
        return (
            %$f,
            stype_name => $cats::source_module_names{$f->{stype}},
            href_problems => url_function('problems', sid => $sid, cid => $f->{contest_id}),
            href_source => url_f('download_import_source', psid => $f->{id}),
            is_jury => $is_jury,
        );
    };

    attach_listview(url_f('import_sources'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('import_sources') ], is_jury => 1) if $is_jury;
}


sub download_import_source_frame
{
    my $psid = param('psid') or return;
    local $dbh->{ib_enable_utf8} = 0;
    my ($fname, $src) = $dbh->selectrow_array(qq~
        SELECT fname, src FROM problem_sources WHERE id = ? AND guid IS NOT NULL~, undef, $psid) or return;
    binmode(STDOUT, ':raw');
    CATS::Web::content_type('text/plain');
    CATS::Web::headers('Content-Disposition' => "inline;filename=$fname");
    print STDOUT $src;
}


sub prizes_frame
{
    $is_root or return;
    if (my $cgid = url_param('delete')) {
        $dbh->do(qq~DELETE FROM contest_groups WHERE id = ?~, undef, $cgid);
        $dbh->commit;
    }

    defined url_param('edit') and return CATS::UI::Prizes::prizes_edit_frame;
    init_listview_template('prizes', 'prizes', 'prizes.html.tt');

    defined param('edit_save') and CATS::UI::Prizes::prizes_edit_save;

    define_columns(url_f('prizes'), 0, 0, [
        { caption => res_str(601), order_by => '2', width => '30%' },
        { caption => res_str(645), order_by => '3', width => '30%' },
        { caption => res_str(646), order_by => '4', width => '40%' },
    ]);

    my $c = $dbh->prepare(qq~
        SELECT cg.id, cg.name, cg.clist,
            (SELECT LIST(rank || ':' || name, ' ') FROM prizes p WHERE p.cg_id = cg.id) AS prizes
            FROM contest_groups cg ~ . order_by);
    $c->execute;

    my $fetch_record = sub {
        my $f = $_[0]->fetchrow_hashref or return ();
        (
            %$f,
            href_edit=> url_f('prizes', edit => $f->{id}),
            href_delete => url_f('prizes', 'delete' => $f->{id}),
        );
    };

    attach_listview(url_f('prizes'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('prizes') ]);
}


sub rank_table
{
    my $template_name = shift;
    init_template('rank_table_content.html.tt');
    $t->param(printable => url_param('printable'));
    my $rt = CATS::RankTable->new;
    $rt->parse_params;
    $rt->rank_table;
    $contest->{title} = $rt->{title};
    my $s = $t->output;

    init_template($template_name);
    $t->param(rank_table_content => $s, printable => (url_param('printable') || 0));
}


sub rank_table_frame
{
    my $hide_ooc = url_param('hide_ooc') || 0;
    my $hide_virtual = url_param('hide_virtual') || 0;
    my $cache = url_param('cache');
    my $show_points = url_param('points');

    #rank_table('main_rank_table.htm');
    #init_template('main_rank_table_content.htm');
    init_template('rank_table.html.tt');

    my $rt = CATS::RankTable->new;
    $rt->get_contest_list_param;
    $rt->get_contests_info($uid);
    $contest->{title} = $rt->{title};

    my @params = (
        hide_ooc => $hide_ooc, hide_virtual => $hide_virtual, cache => $cache,
        clist => $rt->{contest_list}, points => $show_points,
        filter => Encode::decode_utf8(url_param('filter') || undef),
        show_prizes => (url_param('show_prizes') || 0),
    );
    $t->param(href_rank_table_content => url_f('rank_table_content', @params));
    my $submenu =
        [ { href => url_f('rank_table_content', @params, printable => 1), item => res_str(538) } ];
    if ($is_jury)
    {
        push @$submenu,
            { href => url_f('rank_table', @params, cache => 1 - ($cache || 0)), item => res_str(553) },
            { href => url_f('rank_table', @params, points => 1 - ($show_points || 0)), item => res_str(554) };
    }
    $t->param(submenu => $submenu, title_suffix => res_str(529));
}


sub rank_table_content_frame
{
    rank_table('rank_table_iframe.html.tt');
}


sub rank_problem_details
{
    init_template('main_rank_problem_details.htm');
    $is_jury or return;

    my ($pid) = url_param('pid') or return;

    my $runs = $dbh->selectall_arrayref(q~
        SELECT
            R.id, R.state, R.account_id, R.points
        FROM reqs R WHERE R.contest_id = ? AND R.problem_id = ?
        ORDER BY R.id~, { Slice => {} },
        $cid, $pid);

    for (@$runs)
    {
        1;
    }
}


sub about_frame
{
    init_template('about.html.tt');
    my $problem_count = $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM problems P INNER JOIN contests C ON C.id = P.contest_id
            WHERE C.is_hidden = 0 OR C.is_hidden IS NULL~);
    $t->param(problem_count => $problem_count);
}


sub generate_menu
{
    my $logged_on = $sid ne '';

    my @left_menu = (
        { item => $logged_on ? res_str(503) : res_str(500),
          href => $logged_on ? url_function('logout', sid => $sid) : url_function('login') },
        { item => res_str(502), href => url_f('contests') },
        { item => res_str(525), href => url_f('problems') },
        ($is_jury || !$contest->is_practice ? { item => res_str(526), href => url_f('users') } : ()),
        { item => res_str(510),
          href => url_f('console', $is_jury ? () : (uf => $uid || get_anonymous_uid())) },
        ($is_jury ? () : { item => res_str(557), href => url_f('import_sources') }),
    );

    if ($is_jury)
    {
        push @left_menu, (
            { item => res_str(548), href => url_f('compilers') },
            { item => res_str(545), href => url_f('similarity') }
        );
    }
    else
    {
        push @left_menu, (
            { item => res_str(517), href => url_f('compilers') },
            { item => res_str(549), href => url_f('keywords') } );
    }

    unless ($contest->is_practice)
    {
        push @left_menu, ({
            item => res_str(529),
            href => url_f('rank_table', $is_jury ? () : (cache => 1, hide_virtual => !$is_virtual))
        });
    }

    my @right_menu = ();

    if ($uid && (url_param('f') ne 'logout'))
    {
        @right_menu = ( { item => res_str(518), href => url_f('settings') } );
    }

    push @right_menu, (
        { item => res_str(544), href => url_f('about') },
        { item => res_str(501), href => url_f('registration') } );

    attach_menu('left_menu', undef, \@left_menu);
    attach_menu('right_menu', 'about', \@right_menu);
}


sub interface_functions ()
{
    {
        login => \&login_frame,
        logout => \&logout_frame,
        registration => \&registration_frame,
        settings => \&settings_frame,
        contests => \&contests_frame,
        console_content => \&CATS::Console::content_frame,
        console => \&CATS::Console::console_frame,
        console_export => \&CATS::Console::export,
        console_graphs => \&CATS::Console::graphs,
        problems => \&CATS::UI::Problems::problems_frame,
        problems_retest => \&CATS::UI::Problems::problems_retest_frame,
        problem_select_testsets => \&CATS::UI::Problems::problem_select_testsets_frame,
        problem_history => \&CATS::UI::Problems::problem_history_frame,
        users => \&users_frame,
        users_import => \&users_import_frame,
        user_stats => \&user_stats_frame,
        compilers => \&CATS::UI::Compilers::compilers_frame,
        judges => \&CATS::UI::Judges::judges_frame,
        keywords => \&CATS::UI::Keywords::keywords_frame,
        import_sources => \&import_sources_frame,
        prizes => \&prizes_frame,
        download_import_source => \&download_import_source_frame,

        answer_box => \&CATS::UI::Messages::answer_box_frame,
        send_message_box => \&CATS::UI::Messages::send_message_box_frame,

        run_log => \&CATS::RunDetails::run_log_frame,
        view_source => \&CATS::RunDetails::view_source_frame,
        download_source => \&CATS::RunDetails::download_source_frame,
        run_details => \&CATS::RunDetails::run_details_frame,
        diff_runs => \&CATS::RunDetails::diff_runs_frame,

        test_diff => \&CATS::UI::Stats::test_diff_frame,
        compare_tests => \&CATS::UI::Stats::compare_tests_frame,
        rank_table_content => \&rank_table_content_frame,
        rank_table => \&rank_table_frame,
        rank_problem_details => \&rank_problem_details,
        problem_text => \&CATS::Problem::Text::problem_text_frame,
        envelope => \&CATS::UI::Messages::envelope_frame,
        about => \&about_frame,
        static => \&static_frame,

        similarity => \&CATS::UI::Stats::similarity_frame,
        personal_official_results => \&CATS::Contest::personal_official_results,
    }
}


sub accept_request
{
    my $output_file = '';
    if (CATS::StaticPages::is_static_page)
    {
        $output_file = CATS::StaticPages::process_static()
            or return;
    }
    initialize;
    $CATS::Misc::init_time = Time::HiRes::tv_interval(
        $CATS::Misc::request_start_time, [ Time::HiRes::gettimeofday ]);

    unless (defined $t)
    {
        my $function_name = url_param('f') || '';
        my $fn = interface_functions()->{$function_name} || \&about_frame;
        # Function returns -1 if there is no need to generate output, e.g. a redirect was issued.
        ($fn->() || 0) == -1 and return;
    }
    save_settings;

    generate_menu if defined $t;
    generate_output($output_file);
}


sub handler {
    my $r = shift;

    init_request($r);
    $CATS::Misc::request_start_time = [ Time::HiRes::gettimeofday ];
    CATS::DB::sql_connect;
    $dbh->rollback; # In a case of abandoned transaction

    accept_request();
    $dbh->rollback;

    return get_return_code();
}


1;
