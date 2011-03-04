#!/usr/bin/perl
use strict;
use warnings;
no warnings 'redefine';
use encoding 'utf8', STDIN => undef;

use File::Temp qw/tempfile tmpnam mktemp/;
use Encode;
#use CGI::Fast qw(:standard);
use CGI qw(:standard);
#use CGI::Util qw(unescape escape);
#use FCGI;


use Algorithm::Diff;
use Text::Aspell;
use Data::Dumper;
use Storable ();
use Time::HiRes;
use List::Util qw(max);

my $cats_lib_dir;
BEGIN {
    $cats_lib_dir = $ENV{CATS_DIR} || '.';
    $cats_lib_dir =~ s/\/$//;
    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 1;
}
use lib $cats_lib_dir;


use CATS::DB;
use CATS::Constants;
use CATS::BinaryFile;
use CATS::DevEnv;
use CATS::Misc qw(:all);
use CATS::Utils qw(coalesce escape_html url_function state_to_display param_on);
use CATS::Data qw(:all);
use CATS::IP;
use CATS::Problem;
use CATS::RankTable;
use CATS::StaticPages;
use CATS::TeX::Lite;
use CATS::Testset;
use CATS::Contest::Results;
use CATS::User;
use CATS::Console;

use vars qw($html_code $current_pid $spellchecker $text_span $is_static_page);


sub make_sid {
    my @ch = ('A'..'Z', 'a'..'z', '0'..'9');
    join '', map { $ch[rand @ch] } 1..30;
}


sub login_frame
{
    my $json = param('json');
    init_template('main_login.' . ($json ? 'json' : 'htm'));

    my $login = param('login');
    if (!$login)
    {
        $t->param(message => 'No login') if $json;
        return;
    }
    $t->param(login => $login); 
    my $cid = param('contest');
    my $passwd = param('passwd');

    my ($aid, $passwd3, $locked) = $dbh->selectrow_array(qq~
        SELECT id, passwd, locked FROM accounts WHERE login = ?~, {}, $login);

    $aid or return msg(39);

    $passwd3 eq $passwd or return msg(40);

    !$locked or msg(41);

    my $last_ip = CATS::IP::get_ip();

    for (1..20)
    {
        $sid = make_sid;

        $dbh->do(qq~
            UPDATE accounts SET sid = ?, last_login = CURRENT_TIMESTAMP, last_ip = ?
                WHERE id = ?~,
            {}, $sid, $last_ip, $aid
        ) or next;
        $dbh->commit;

        my $cid =
            url_param('cid') ||
            $dbh->selectrow_array(qq~SELECT id FROM contests WHERE ctype = 1~);
        if ($json)
        {
            $t->param(sid => $sid, cid => $cid);
            return;
        }
        {
            $t = undef;
            print redirect(-uri => url_function('contests', sid => $sid, cid => $cid));
            return -1;
        }
    }
    die 'Can not generate sid';
}


sub logout_frame
{
    init_template('main_logout.htm');

    $cid = '';
    $sid = '';
    $t->param(href_login => url_f('login'));

    $dbh->do(qq~UPDATE accounts SET sid = NULL WHERE id = ?~, {}, $uid);
    $dbh->commit;
    0;
}


sub contests_new_frame
{
    init_template('main_contests_new.htm');

    my $date = $dbh->selectrow_array(q~SELECT CURRENT_TIMESTAMP FROM RDB$DATABASE~);
    $date =~ s/\s*$//;
    $t->param(
        start_date => $date, freeze_date => $date,
        finish_date => $date, open_date => $date,
        can_edit => 1,
        is_hidden => !$is_root,
        href_action => url_f('contests')
    );
}


sub contest_checkbox_params()
{qw(
    free_registration run_all_tests
    show_all_tests show_test_resources show_checker_comment
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
            show_test_resources, show_checker_comment, is_official, show_packages, local_only,
            is_hidden, show_frozen_reqs
        ) VALUES(
            ?, ?, ?, ?, ?, ?, ?, ?,
            0,
            ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)~,
        {},
        $cid, @$p{contest_string_params()},
        @$p{contest_checkbox_params()}
    );

    # автоматически зарегистрировать всех администраторов как жюри
    my $root_accounts = $dbh->selectcol_arrayref(qq~
        SELECT id FROM accounts WHERE srole = ?~, undef, $cats::srole_root);
    push @$root_accounts, $uid unless $is_root; # пользователь с ролью contests_creator
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

    init_template('main_contest_params.htm');  

    my $p = $dbh->selectrow_hashref(qq~
        SELECT
            title AS contest_name,
            start_date,
            freeze_date,
            finish_date,
            defreeze_date AS open_date,
            1 - closed AS free_registration,
            run_all_tests, show_all_tests, show_test_resources, show_checker_comment,
            is_official, show_packages, local_only, rules, is_hidden, max_reqs
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
            show_test_resources=?, show_checker_comment=?, is_official=?, show_packages=?,
            local_only=?, is_hidden=?, show_frozen_reqs=0
        WHERE id=?~,
        {},
        @$p{contest_string_params()},
        @$p{contest_checkbox_params()},
        $edit_cid
    );
    $dbh->commit;
    # если переименовали текущий турнир, сразу изменить заголовок окна
    if ($edit_cid == $cid)
    {
        $contest->{title} = $p->{contest_name};
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
    
    # В официальных турнирах виртуальное участие резрешено только после окончания.
    $contest->{time_since_finish} >= 0 || !$contest->{is_official}
        or return msg(122);

    !$contest->{closed}
        or return msg(105);

    # при повторной регистрации удаляем старые результаты
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
    # HACK: начальная страница -- список турниров, выводится очень часто
    # при отсутствии поиска выбираем только первую страницу + 1 запись.
    # my $s = $settings->{$listview_name};
    # (($s->{page} || 0) == 0 && !$s->{search} ? 'FIRST ' . ($s->{rows} + 1) : '') .
    q~c.ctype, c.id, c.title,
    c.start_date, c.finish_date, c.closed, c.is_official, c.rules~
}


sub contests_submenu_filter
{
    my $f = $settings->{contests}->{filter} || '';
    {
        'all' => '',
        'official' => 'AND C.is_official = 1 ',
        'unfinished' => 'AND CURRENT_TIMESTAMP <= finish_date ',
        'current' => 'AND CURRENT_TIMESTAMP BETWEEN start_date AND finish_date ',
    }->{$f} || '';
}


sub authenticated_contests_view ()
{
    my $cf = contest_fields();
    my $sth = $dbh->prepare(qq~
        SELECT
            $cf, CA.is_virtual, CA.is_jury, CA.id AS registered, C.is_hidden
        FROM contests C LEFT JOIN
            contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        WHERE
            (CA.account_id IS NOT NULL OR COALESCE(C.is_hidden, 0) = 0) ~ .
            contests_submenu_filter() . order_by);
    $sth->execute($uid);

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
        print redirect(-uri => url_f('rank_table', clist => join ',', @clist));
        return -1;
    }

    return contests_new_frame
        if defined url_param('new') && $CATS::Misc::can_create_contests;

    try_contest_params_frame and return;

    my $ical = param('ical');
    my $json = param('json');
    return if $ical && $json;
    init_listview_template('contests', 'contests',
        'main_contests.' .  ($ical ? 'ics' : $json ? 'json' : 'htm'));

    if (defined url_param('delete') && $is_root)
    {
        my $cid = url_param('delete');
        $dbh->do(qq~DELETE FROM contests WHERE id = ?~, {}, $cid);
        $dbh->commit;
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
            href_item => url_f('contests', page => 0, filter => $_->{n}),
            item_name => res_str($_->{i}),
            selected => $settings->{contests}->{filter} eq $_->{n}, 
        }, { n => 'all', i => 558 }, { n => 'official', i => 559 }, { n => 'unfinished', i => 560 }),
        ($CATS::Misc::can_create_contests ?
            { href_item => url_f('contests', new => 1), item_name => res_str(537) } : ()),
        { href_item => url_f('contests',
            ical => 1, rows => 50, filter => $settings->{contests}->{filter}), item_name => res_str(562) },
    ];
    $t->param(
        submenu => $submenu,
        authorized => defined $uid,
        href_contests => url_f('contests'),
        editable => $is_root,
        is_registered => defined $uid && get_registered_contestant(contest_id => $cid) || 0,
    );
}

sub problems_change_status ()
{
    my $cpid = param('change_status')
      or return msg(54);
    
    my $new_status = param('status');
    exists problem_status_names()->{$new_status} or return;
    
    $dbh->do(qq~
        UPDATE contest_problems SET status = ?
            WHERE contest_id = ? AND id = ?~, {},
        $new_status, $cid, $cpid);
    $dbh->commit;
    # Возможно изменение статуса hidden
    CATS::StaticPages::invalidate_problem_text(cid => $cid);
}

sub problems_change_code ()
{
    my $cpid = param('change_code')
      or return msg(54);
    my $new_code = param('code') || '';
    $new_code =~ /^[A-Z]$/ or return;
    $dbh->do(qq~
        UPDATE contest_problems SET code = ?
            WHERE contest_id = ? AND id = ?~, {},
        $new_code, $cid, $cpid);
    $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(cid => $cid);
}

sub show_unused_problem_codes ()
{
    my $c = $dbh->selectcol_arrayref(qq~
        SELECT code FROM contest_problems WHERE contest_id = ?~, {},
        $cid
    );
    my %used_codes;
    $used_codes{$_ || ''} = undef for @$c;
    
    my @unused_codes = grep !exists($used_codes{$_}), 'A'..'Z';
    
    $t->param(
        code_array => [ map({ code => $_ }, @unused_codes) ],
        too_many_problems => !@unused_codes,
    );
}


sub problems_new_frame
{
    init_template('main_problems_new.htm');

    show_unused_problem_codes;
    $t->param(href_action => url_f('problems'));
}


sub add_problem_to_contest
{
    my ($pid, $problem_code) = @_;
    CATS::StaticPages::invalidate_problem_text(cid => $cid);
    return $dbh->do(qq~
        INSERT INTO contest_problems(id, contest_id, problem_id, code, status)
            VALUES (?,?,?,?,?)~, {},
        new_id, $cid, $pid, $problem_code,
        # Если не-архивный турнир уже идёт, добавляемые задачи сразу получают статус hidden
        $contest->{time_since_start} > 0 && $contest->{ctype} == 0 ?
            $cats::problem_st_hidden : $cats::problem_st_ready);
}


sub save_uploaded_file
{
    my ($file) = @_;
    my ($fh, $fname) = tmpnam;
    my ($br, $buffer);
    #$file->open(':raw');
    #binmode $fh, ':raw'; binmode $file, ':raw'; warn $file;
    while ($br = sysread($file, $buffer, 16384))
    {
        syswrite($fh, $buffer, $br);
    }
    close $fh;
    return $fname;
}


sub check_problem_code
{
    my ($problem_code) = @_;
    if ($contest->is_practice)
    {
        undef $$problem_code;
        return 1;
    }
    $$problem_code =~ /^[A-Z0-9]$/ or return msg(134);

    my ($prev) = $dbh->selectrow_array(q~
        SELECT id FROM contest_problems WHERE contest_id = ? AND code = ?~, {},
        $cid, $$problem_code);
    return $prev ? msg(133) : 1;
}


sub problems_new_save
{
    my $file = param('zip') || '';
    $file =~ /\.(zip|ZIP)$/
        or return msg(53);
    my $fname = save_uploaded_file($file);
    my $problem_code = param('problem_code');
    check_problem_code(\$problem_code) or return;

    my CATS::Problem $p = CATS::Problem->new;
    my $error = $p->load($fname, $cid, new_id, 0);
    $t->param(problem_import_log => $p->encoded_import_log());
    $error ||= !add_problem_to_contest($p->{id}, $problem_code);

    $error ? $dbh->rollback : $dbh->commit;
    msg(52) if $error;
    unlink $fname;
}


sub problems_link_save
{       
    my $pid = param('problem_id')
        or return msg(104);

    my $problem_code = param('problem_code');
    check_problem_code(\$problem_code) or return;
    my $move_problem = param('move');
    if ($move_problem)
    {
        # Нужны права жюри в турнире, из которого перемещаем задачу
        # Проверим заранее, чтобы не нужно было делать rollback
        my ($j) = $dbh->selectrow_array(q~
            SELECT CA.is_jury FROM contest_accounts CA
                INNER JOIN contests C ON CA.contest_id = C.id
                INNER JOIN problems P ON C.id = P.contest_id
            WHERE CA.account_id = ? AND P.id = ?~, undef,
            $uid, $pid);
        $j or return msg(135);
    }
    add_problem_to_contest($pid, $problem_code);
    if ($move_problem)
    {
        $dbh->do(q~
            UPDATE problems SET contest_id = ? WHERE id = ?~, undef, $cid, $pid);
    }
    $dbh->commit;
}


sub problems_replace
{
    my $pid = param('problem_id')
        or return msg(54);
    my $file = param('zip') || '';
    $file =~ /\.(zip|ZIP)$/
        or return msg(53);
    my ($contest_id, $old_title) = $dbh->selectrow_array(qq~
        SELECT contest_id, title FROM problems WHERE id=?~, {}, $pid);
     
    # Запрет на замену прилинкованных задач. По-первых, для надёжности,
    # а во-вторых, это секурити -- чтобы не проверять is_jury($contest_id).
    $contest_id == $cid
        or return msg(117);
    my $fname = save_uploaded_file($file);

    my CATS::Problem $p = CATS::Problem->new;
    $p->{old_title} = $old_title unless param('allow_rename');
    my $error = $p->load($fname, $cid, $pid, 1);
    $t->param(problem_import_log => $p->encoded_import_log());

    $error ? $dbh->rollback : $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(pid => $pid);
    msg(52) if $error;
    #unlink $fname;
}


sub problems_add_new
{
    my $file = param('zip') || '';
    $file =~ /\.(zip|ZIP)$/
        or return msg(53);
    my $fname = save_uploaded_file($file);

    my $problem_code;
    if (!$contest->is_practice)
    {
        my $c = $dbh->selectcol_arrayref(qq~
            SELECT code FROM contest_problems WHERE contest_id = ?~, {},
            $cid
        );
        my %used_codes;
        $used_codes{$_ || ''} = undef for @$c;
        ($problem_code) = grep !exists($used_codes{$_}), 'A'..'Z';
    }

    my CATS::Problem $p = CATS::Problem->new;
    my $error = $p->load($fname, $cid, new_id, 0);
    $t->param(problem_import_log => $p->encoded_import_log());
    $error ||= !add_problem_to_contest($p->{id}, $problem_code);

    $error ? $dbh->rollback : $dbh->commit;
    msg(52) if $error;
    unlink $fname;
}


sub problems_all_frame
{
    init_listview_template('link_problem', 'link_problem', 'main_problems_link.htm');

    my $link = url_param('link');
    my $kw = url_param('kw');

    $link and show_unused_problem_codes;

    my $cols = [
        { caption => res_str(602), order_by => '2', width => '30%' }, 
        { caption => res_str(603), order_by => '3', width => '30%' },                    
        { caption => res_str(604), order_by => '4', width => '10%' },
        #{ caption => res_str(605), order_by => '5', width => '10%' },
        #{ caption => res_str(606), order_by => '6', width => '10%' },
    ];
    define_columns(url_f('problems', link => $link, kw => $kw), 0, 0, $cols);

    my $where =
        $is_root ? {
            cond => [], 'params' => [] }
        : !$link ? {
            cond => ['CURRENT_TIMESTAMP > C.finish_date AND (C.is_hidden = 0 OR C.is_hidden IS NULL)'],
            'params' => [] }
        : {
            cond => [q~
            (
                EXISTS (
                    SELECT 1 FROM contest_accounts
                    WHERE contest_id = C.id AND account_id = ? AND is_jury = 1
                    ) OR CURRENT_TIMESTAMP > C.finish_date
            )~],
            params => [$uid]
        };
      
    if ($kw) {
        push @{$where->{cond}}, q~
            (EXISTS (SELECT 1 FROM problem_keywords PK WHERE PK.problem_id = P.id AND PK.keyword_id = ?))~;
        push @{$where->{params}}, $kw;
    }

    my $where_cond = join(' AND ', @{$where->{cond}}) || '1=1';
    my $c = $dbh->prepare(qq~
        SELECT P.id, P.title, C.title, C.id,
            (SELECT
                SUM(CASE R.state WHEN $cats::st_accepted THEN 1 ELSE 0 END) || ' / ' ||
                SUM(CASE R.state WHEN $cats::st_wrong_answer THEN 1 ELSE 0 END) || ' / ' ||
                SUM(CASE R.state WHEN $cats::st_time_limit_exceeded THEN 1 ELSE 0 END)
                FROM reqs R WHERE R.problem_id = P.id
            ),
            (SELECT COUNT(*) FROM contest_problems CP WHERE CP.problem_id = P.id AND CP.contest_id = ?)
        FROM problems P INNER JOIN contests C ON C.id = P.contest_id
        WHERE $where_cond ~ . order_by);
    $c->execute($cid, @{$where->{params}});

    my $fetch_record = sub($)
    {
        my ($pid, $problem_name, $contest_name, $contest_id, $counts, $linked) = $_[0]->fetchrow_array
            or return ();
        return ( 
            href_view_problem => url_f('problem_text', pid => $pid),
            href_view_contest => url_function('problems', sid => $sid, cid => $contest_id),
            linked => $linked || !$link,
            problem_id => $pid,
            problem_name => $problem_name, 
            contest_name => $contest_name, 
            counts => $counts,
        );
    };
         
    attach_listview(url_f('problems', link => $link, kw => $kw), $fetch_record, $c);

    $t->param(
        href_action => url_f($kw ? 'keywords' : 'problems'),
        link => !$contest->is_practice && $link, move => url_param('move') || 0, is_jury => $is_jury);
    
    $c->finish;
}


sub download_problem
{
    undef $t;

    my $pid = param('download');
    # Если hash уже есть, то файл не вытаскиваем, а выдаём ссылку на имеющийся.
    # Предполагаем, что размер пакета достаточно велик,
    # поэтому имеет смысл выбирать его отдельным запросом.
    my ($hash) = $dbh->selectrow_array(qq~
        SELECT hash FROM problems WHERE id = ?~, undef, $pid);
    my $already_hashed = ensure_problem_hash($pid, \$hash);
    my $fname = "./download/pr/problem_$hash.zip";
    unless($already_hashed && -f $fname)
    {
        my ($zip) = eval { $dbh->selectrow_array(qq~
            SELECT zip_archive FROM problems WHERE id = ?~, undef, $pid); };
        if ($@)
        {
            print header(), $@;
            return;
        }
        CATS::BinaryFile::save(cats_dir() . $fname, $zip);
    }
    print redirect(-uri => $fname);
    -1;
}


sub upload_source
{
    my ($file) = @_;
    my $src = '';
    use bytes;
    while (read($file, my $buffer, 4096))
    {
        length $src < 32767 or return;
        $src .= $buffer;
    }
    return $src;
}


sub problems_submit
{
    # Проверяем параметры заранее, чтобы не делать бесполезных обращений к БД.
    my $pid = param('problem_id')
        or return msg(12);

    my $file = param('source');
    $file ne '' and length($file) <= 200 or return msg(9);

    defined param('de_id') or return msg(14);

    my $time_since_finish = 0;
    unless ($is_jury)
    {
        (my $time_since_start, $time_since_finish, my $is_official, my $status) = $dbh->selectrow_array(qq~
            SELECT
                CURRENT_TIMESTAMP - $virtual_diff_time - C.start_date,
                CURRENT_TIMESTAMP- $virtual_diff_time - C.finish_date,
                C.is_official, CP.status
            FROM contests C, contest_problems CP
            WHERE CP.contest_id = C.id AND C.id = ? AND CP.problem_id = ?~, {},
            $cid, $pid);

        $time_since_start >= 0
            or return msg(80);
        $time_since_finish <= 0 || $is_virtual
            or return msg(81);
        !defined $status || $status < $cats::problem_st_disabled
            or return msg(124);

        # во время официального турнира отправка заданий во все остальные временно прекращается
        if (!$is_official || $is_virtual)
        {
            my ($current_official) = $contest->current_official;
            !$current_official
                or return msg(123, $current_official->{title});
        }
    }
    
    my $submit_uid = $uid;
    if (!defined $submit_uid && $contest->is_practice)
    {
        $submit_uid = get_anonymous_uid();
    }

    # Защита от Denial of Service -- запрещаем посылать решения слишком часто
    my $prev = $dbh->selectcol_arrayref(q~
        SELECT FIRST 2 CURRENT_TIMESTAMP - R.submit_time FROM reqs R
        WHERE R.account_id = ?
        ORDER BY R.submit_time DESC~, {},
        $submit_uid);
    my $SECONDS_PER_DAY = 24 * 60 * 60;
    if (($prev->[0] || 1) < 3/$SECONDS_PER_DAY || ($prev->[1] || 1) < 60/$SECONDS_PER_DAY)
    {
        return msg(131);
    }

    my $prev_reqs_count;
    if ($contest->{max_reqs} && !$is_jury)
    {
        $prev_reqs_count = $dbh->selectrow_array(q~
            SELECT COUNT(*) FROM reqs R
            WHERE R.account_id = ? AND R.problem_id = ? AND R.contest_id = ?~, {},
            $submit_uid, $pid, $cid);
        return msg(137) if $prev_reqs_count >= $contest->{max_reqs};
    }

    my $src = upload_source($file);
    defined($src) or return msg(10);
    $src or return msg(11);
    my $did = param('de_id');

    if (param('de_id') eq 'by_extension')
    {
        my $de_list = CATS::DevEnv->new($dbh, active_only => 1);
        my $de = $de_list->by_file_extension($file)
            or return msg(13);
        $did = $de->{id};
        $t->param(de_name => $de->{description});
    }

    # Защита от спама и случайных ошибок -- запрещаем повторяющийся исходный код.
    my $source_hash = CATS::Utils::source_hash($src);
    my ($same_source) = $dbh->selectrow_array(qq~
        SELECT FIRST 1 S.req_id
        FROM sources S INNER JOIN reqs R ON S.req_id = R.id
        WHERE
            R.account_id = ? AND R.problem_id = ? AND
            R.contest_id = ? AND S.hash = ? AND S.de_id = ?~, {},
        $submit_uid, $pid, $cid, $source_hash, $did);
    $same_source and return msg(132);

    my $rid = new_id;

    $dbh->do(qq~
        INSERT INTO reqs (
            id, account_id, problem_id, contest_id, 
            submit_time, test_time, result_time, state, received
        ) VALUES (
            ?,?,?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,?,?)~,
        {},
        $rid, $submit_uid, $pid, $cid, $cats::st_not_processed, 0);

    my $s = $dbh->prepare(qq~
        INSERT INTO sources(req_id, de_id, src, fname, hash) VALUES (?,?,?,?,?)~);
    $s->bind_param(1, $rid);
    $s->bind_param(2, $did);
    $s->bind_param(3, $src, { ora_type => 113 } ); # blob
    $s->bind_param(4, "$file");
    $s->bind_param(5, $source_hash);
    $s->execute;
    $dbh->commit;

    $t->param(solution_submitted => 1, href_console => url_f('console'));
    $time_since_finish > 0 ? msg(87) :
    defined $prev_reqs_count ? msg(88, $contest->{max_reqs} - $prev_reqs_count - 1) :
    msg(15);
}


sub problems_submit_std_solution
{
    my $pid = param('problem_id');

    defined $pid
        or return msg(12);

    my $ok = 0;
    
    my $c = $dbh->prepare(qq~
        SELECT src, de_id, fname 
        FROM problem_sources 
        WHERE problem_id = ? AND (stype = ? OR stype = ?)~);
    $c->execute($pid, $cats::solution, $cats::adv_solution);

    while (my ($src, $did, $fname) = $c->fetchrow_array)
    {
        my $rid = new_id;

        $dbh->do(qq~
            INSERT INTO reqs(
                id, account_id, problem_id, contest_id,
                submit_time, test_time, result_time, state, received
            ) VALUES (
                ?, ?, ?, ?,
                CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?, 0)~,
            {}, $rid, $uid, $pid, $cid, $cats::st_not_processed
        );

        my $s = $dbh->prepare(qq~
            INSERT INTO sources(req_id, de_id, src, fname) VALUES (?, ?, ?, ?)~);
        $s->bind_param(1, $rid);
        $s->bind_param(2, $did);
        $s->bind_param(3, $src, { ora_type => 113 } ); # blob
        $s->bind_param(4, $fname);
        $s->execute;
        
        $ok = 1;
    }
    
    if ($ok)
    {
        $dbh->commit; 
        $t->param(solution_submitted => 1, href_console => url_f('console'));
        msg(107);
    }
    else
    {
        msg(106);
    }
}


sub problems_mass_retest()
{
    my @retest_pids = param('problem_id')
        or return msg(12);
    my $all_runs = param('all_runs');
    my $count = 0;
    for my $retest_pid (@retest_pids)
    {
        my $runs = $dbh->selectall_arrayref(q~
            SELECT id, account_id, state FROM reqs
            WHERE contest_id = ? AND problem_id = ? ORDER BY id DESC~,
            { Slice => {} },
            $cid, $retest_pid
        );
        my %accounts = ();
        for (@$runs)
        {
            next if !$all_runs && $accounts{$_->{account_id}};
            $accounts{$_->{account_id}} = 1;
            ($_->{state} || 0) != $cats::st_ignore_submit &&
                enforce_request_state(request_id => $_->{id}, state => $cats::st_not_processed)
                    and ++$count;
        }
        $dbh->commit;
    }
    return msg(128, $count);
}


sub problems_recalc_points()
{
    my @pids = param('problem_id') or return msg(12);
    $dbh->do(q~
        UPDATE reqs SET points = NULL
        WHERE contest_id = ? AND problem_id IN (~ . join(',', @pids) . q~)~, undef,
        $cid);
    $dbh->commit;
}


sub problem_status_names()
{
    return {
        $cats::problem_st_ready     => res_str(700),
        $cats::problem_st_suspended => res_str(701),
        $cats::problem_st_disabled  => res_str(702),
        $cats::problem_st_hidden    => res_str(703),
    };
}


sub problems_frame_jury_action
{
    $is_jury or return;

    defined param('link_save') and return problems_link_save;
    defined param('new_save') and return problems_new_save;
    defined param('change_status') and return problems_change_status;
    defined param('change_code') and return problems_change_code;
    defined param('replace') and return problems_replace;
    defined param('add_new') and return problems_add_new;
    defined param('std_solution') and return problems_submit_std_solution;
    defined param('mass_retest') and return problems_mass_retest;
    my $cpid = url_param('delete');
    if (defined $cpid)
    {
        my ($pid, $old_contest) = $dbh->selectrow_array(q~
            SELECT problem_id, contest_id FROM contest_problems WHERE id = ?~, undef,
            $cpid) or return;

        $dbh->do(qq~DELETE FROM contest_problems WHERE id = ?~, undef, $cpid);
        my ($ref_count) = $dbh->selectrow_array(qq~
            SELECT COUNT(*) FROM contest_problems WHERE problem_id = ?~, undef, $pid);
        if ($ref_count)
        {
            # Если на задачу ссылается хотя бы один турнир, переносим все попытки
            # в "главный" турнир. Из главного турнира задача должна удаляться последней.
            # Это ограничение можно обойти, произвольно назначая новый главный турнир.
            my ($new_contest) = $dbh->selectrow_array(q~
                SELECT contest_id FROM problems WHERE id = ?~, undef, $pid);
            ($new_contest != $old_contest) or return msg(136);
            $dbh->do(q~
                UPDATE reqs SET contest_id = ? WHERE problem_id = ? AND contest_id = ?~, undef,
                $new_contest, $pid, $old_contest);
        }
        else
        {
            $dbh->do(qq~DELETE FROM problems WHERE id = ?~, undef, $pid);
        }
        $dbh->commit;
    }
}


sub problem_select_testsets
{
    $is_jury or return;
    my $cpid = param('cpid') or return;
    
    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.id, P.title, CP.id AS cpid, CP.testsets
        FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE CP.id = ?~, undef, $cpid);
    my $testsets = $dbh->selectall_arrayref(q~
        SELECT * FROM testsets WHERE problem_id = ?~, { Slice => {} },
        $problem->{id});

    if (param('save'))
    {
        my %sel;
        @sel{param('sel')} = undef;
        $_->{selected} = exists $sel{$_->{id}} for @$testsets;
        my $ts_list = join ' ', map $_->{name}, grep $_->{selected}, @$testsets;
        $dbh->do(q~
            UPDATE contest_problems SET testsets = ? WHERE id = ?~, undef,
            $ts_list, $problem->{cpid});
        $dbh->commit;
        print redirect(-uri => url_f('problems'));
        return -1;
    }

    my %sel;
    @sel{split /\s+/, $problem->{testsets} || ''} = undef;
    $_->{selected} = exists $sel{$_->{name}} for @$testsets;

    init_template('main_problem_select_testsets.htm');
    $t->param("problem_$_" => $problem->{$_}) for keys %$problem;
    $t->param(testsets => $testsets, href_select_testsets => url_f('problem_select_testsets'));
}


sub problems_retest_frame
{
    $is_jury && !$contest->is_practice or return;
    init_listview_template('problems_retest', 'problems', 'main_problems_retest.htm');

    defined param('mass_retest') and problems_mass_retest;
    defined param('recalc_points') and problems_recalc_points;

    my @cols = (
        { caption => res_str(602), order_by => '3', width => '30%' }, # название
        { caption => res_str(639), order_by => '7', width => '10%' }, # в очереди
        { caption => res_str(632), order_by => '6', width => '10%' }, # статус
        { caption => res_str(605), order_by => '5', width => '10%' }, # набор тестов
        { caption => res_str(604), order_by => '8', width => '10%' }, # ok/wa/tl
    );
    define_columns(url_f('problems_retest'), 0, 0, [ @cols ]);
    my $reqs_count_sql = 'SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state =';
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            CP.code, P.title AS problem_name, CP.testsets, CP.status,
            ($reqs_count_sql $cats::st_accepted) AS accepted_count,
            ($reqs_count_sql $cats::st_wrong_answer) AS wrong_answer_count,
            ($reqs_count_sql $cats::st_time_limit_exceeded) AS time_limit_count,
            (SELECT COUNT(*) FROM reqs R
                WHERE R.contest_id = CP.contest_id AND R.problem_id = CP.problem_id AND
                R.state < $cats::request_processed) AS in_queue
        FROM problems P INNER JOIN contest_problems CP ON CP.problem_id = P.id
        WHERE CP.contest_id = ?~ . order_by);
    $sth->execute($cid);

    my $total_queue = 0;
    my $fetch_record = sub($)
    {            
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
        my $psn = problem_status_names();
        $total_queue += $c->{in_queue};
        return (
            status => $psn->{$c->{status}},
            href_view_problem => url_f('problem_text', cpid => $c->{cpid}),
            problem_id => $c->{pid},
            code => $c->{code},
            problem_name => $c->{problem_name},
            accept_count => $c->{accepted_count},
            wa_count => $c->{wrong_answer_count},
            tle_count => $c->{time_limit_count},
            testsets => $c->{testsets} || '*',
            in_queue => $c->{in_queue},
            href_select_testsets => url_f('problem_select_testsets', cpid => $c->{cpid}),
        );
    };
    attach_listview(url_f('problems_retest'), $fetch_record, $sth);

    $sth->finish;

    $t->param(total_queue => $total_queue);
}


sub problems_frame
{
    my $my_is_team =
        $is_jury || $contest->is_practice ||
        $is_team && $contest->{time_since_finish} - $virtual_diff_time < 0;
    my $show_packages = 1;
    unless ($is_jury)
    {
        $show_packages = $contest->{show_packages};
        my $local_only = $contest->{local_only};
        if ($contest->{time_since_start} < 0)
        {
            init_template('main_problems_inaccessible.htm');
            return msg(130);
        }
        if ($local_only)
        {
            my $is_remote;
            if ($uid)
            { 
                ($is_remote) = $dbh->selectrow_array(qq~
                    SELECT is_remote FROM contest_accounts WHERE contest_id = ? AND account_id = ?~,
                    {}, $cid, $uid);
            }
            if (!defined $is_remote || $is_remote)
            {
                init_template('main_problems_inaccessible.htm');
                return msg(129);
            }
        }
    }

    $is_jury && defined url_param('new') and return problems_new_frame;
    $is_jury && defined url_param('link') and return problems_all_frame;
    defined url_param('kw') and return problems_all_frame;

    defined param('download') && $show_packages and return download_problem;

    my $json = param('json');
    init_listview_template('problems' . ($contest->is_practice ? '_practice' : ''),
        'problems', 'main_problems.' . ($json ? 'json' : 'htm'));
    problems_frame_jury_action;

    if (defined param('submit'))
    {
        problems_submit;
    }

    my @cols = (
        { caption => res_str(602), order_by => ($contest->is_practice ? '4' : '3'), width => '30%' },
        ($is_jury ?
        (
            { caption => res_str(632), order_by => '11', width => '10%' }, # статус
            { caption => res_str(605), order_by => '15', width => '10%' }, # набор тестов
            { caption => res_str(635), order_by => '13', width => '5%' }, # кто изменил
            { caption => res_str(634), order_by => 'P.upload_date', width => '10%' }, # дата изменения
        )
        : ()
        ),
        ($contest->is_practice ?
        { caption => res_str(603), order_by => '5', width => '20%' } : ()
        ),
        { caption => res_str(604), order_by => '6', width => '10%' },
    );
    define_columns(url_f('problems'), 0, 0, \@cols);

    my $reqs_count_sql = 'SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state =';
    my $account_condition = $contest->is_practice ? '' : ' AND D.account_id = ?';
    my $select_code = $contest->is_practice ? 'NULL' : 'CP.code';
    my $hidden_problems = $is_jury ? '' : " AND (CP.status IS NULL OR CP.status < $cats::problem_st_hidden)";
    # TODO: учитывать testsets
    my $test_count_sql = $is_jury ? '(SELECT COUNT(*) FROM tests T WHERE T.problem_id = P.id) AS test_count,' : '';
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            ${select_code} AS code, P.title AS problem_name, OC.title AS contest_name,
            ($reqs_count_sql $cats::st_accepted$account_condition) AS accepted_count,
            ($reqs_count_sql $cats::st_wrong_answer$account_condition) AS wrong_answer_count,
            ($reqs_count_sql $cats::st_time_limit_exceeded$account_condition) AS time_limit_count,
            P.contest_id - CP.contest_id AS is_linked,
            OC.id AS original_contest_id, CP.status,
            P.upload_date,
            (SELECT A.login FROM accounts A WHERE A.id = P.last_modified_by) AS last_modified_by,
            SUBSTRING(P.explanation FROM 1 FOR 1) AS has_explanation,
            $test_count_sql CP.testsets
        FROM problems P, contest_problems CP, contests OC
        WHERE CP.problem_id = P.id AND OC.id = P.contest_id AND CP.contest_id = ?$hidden_problems
        ~ . order_by
    );
    if ($contest->is_practice)
    {
        $sth->execute($cid);
    }
    else
    {
        my $aid = $uid || 0; # на случай анонимного пользователя
        # ORDER BY subselect требует повторного указания параметра
        $sth->execute($aid, $aid, $aid, $cid); #, (order_by =~ /^ORDER BY\s+(5|6|7)\s+/ ? ($aid) : ()));
    }

    my @status_list;
    if ($is_jury)
    {
        my $n = problem_status_names();
        for (sort keys %$n)
        {
            push @status_list, { id => $_, name => $n->{$_} }; 
        }
        $t->param(status_list => \@status_list, editable => 1);
    }

    my $fetch_record = sub($)
    {            
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
        my $psn = problem_status_names();
        return (
            href_delete   => url_f('problems', 'delete' => $c->{cpid}),
            href_change_status => url_f('problems', 'change_status' => $c->{cpid}),
            href_change_code => url_f('problems', 'change_code' => $c->{cpid}),
            href_replace  => url_f('problems', replace => $c->{cpid}),
            href_download => url_f('problems', download => $c->{pid}),
            href_compare_tests => $is_jury && url_f('compare_tests', pid => $c->{pid}),
            href_original_contest =>
                url_function('problems', sid => $sid, cid => $c->{original_contest_id}, set_contest => 1),
            show_packages => $show_packages,
            is_practice => $contest->is_practice,
            editable => $is_jury,
            status => $c->{status},
            disabled => !$is_jury && $c->{status} == $cats::problem_st_disabled,
            is_team => $my_is_team,
            href_view_problem => url_f('problem_text', cpid => $c->{cpid}),
            href_explanation => $show_packages && $c->{has_explanation} ?
                url_f('problem_text', cpid => $c->{cpid}, explain => 1) : '',
            problem_id => $c->{pid},
            code => $c->{code},
            problem_name => $c->{problem_name},
            is_linked => $c->{is_linked},
            contest_name => $c->{contest_name},
            accept_count => $c->{accepted_count},
            wa_count => $c->{wrong_answer_count},
            tle_count => $c->{time_limit_count},
            upload_date => $c->{upload_date},
            last_modified_by => $c->{last_modified_by},
            testsets => $c->{testsets} || '*',
            test_count => $c->{test_count},
            href_select_testsets => url_f('problem_select_testsets', cpid => $c->{cpid}),
            status_list => [
                map {{ id => $_, name => $psn->{$_}, selected => $c->{status} == $_ }} sort keys %$psn
            ],
            code_array => [ map {{code => $_, selected => ($c->{code} || '') eq $_ }} 'A' .. 'Z' ],
        );
    };

    attach_listview(url_f('problems'), $fetch_record, $sth);

    $sth->finish;

    my $de_list = CATS::DevEnv->new($dbh, active_only => 1);
    my @de = (
        { de_id => 'by_extension', de_name => res_str(536) },
        map {{ de_id => $_->{id}, de_name => $_->{description} }} @{$de_list->{_de_list}} );

    my $pt_url = sub {{
        href_item => $_[0], item_name => ($_[1] || res_str(538)), item_target => '_blank'
    }};
    my @submenu = ();
    if ($is_jury)
    {
        push @submenu,
            $pt_url->(url_f('problem_text', nospell => 1, nokw => 1, notime => 1, noformal => 1)),
            $pt_url->(url_f('problem_text'), res_str(555))
            unless $contest->is_practice;
        push @submenu,
            { href_item => url_f('problems', link => 1), item_name => res_str(540) },
            { href_item => url_f('problems', link => 1, move => 1), item_name => res_str(551) },
            { href_item => url_f('problems_retest'), item_name => res_str(556) };
    }
    else
    {
        push @submenu, $pt_url->(CATS::StaticPages::url_static('problem_text', cid => $cid))
            unless $contest->is_practice;
    }

    $t->param(submenu => \@submenu, title_suffix => res_str(525));
    $t->param(is_team => $my_is_team, is_practice => $contest->is_practice, de_list => \@de);
}


sub greedy_cliques
{
    my (@equiv_tests) = @_;
    my $eq_lists = [];
    while (@equiv_tests)
    {
        my $eq = [ @{$equiv_tests[0]}{qw(t1 t2)} ];
        shift @equiv_tests;
        my %cnt;
        for my $et (@equiv_tests)
        {
            $cnt{$et->{t2}}++ if grep $_ == $et->{t1}, @$eq;
        }
        my $neq = @$eq;
        for my $k (sort keys %cnt)
        {
            next unless $cnt{$k} == $neq;
            push @$eq, $k;
            my @new_et;
            for my $et (@equiv_tests)
            {
                push @new_et, $et unless $et->{t2} == $k && grep $_ == $et->{t1}, @$eq;
            }
            @equiv_tests = @new_et;
        }
        push @$eq_lists, { eq => join ',', @$eq };
    }
    $eq_lists;
}


sub compare_tests_frame
{
    init_template('main_compare_tests.htm');
    $is_jury or return;
    my ($pid) = param('pid') or return;
    my ($pt) = $dbh->selectrow_array(q~
        SELECT title FROM problems WHERE id = ?~, undef,
        $pid);
    $pt or return;
    $t->param(problem_title => $pt);
    
    my $totals = $dbh->selectall_hashref(qq~
        SELECT
            SUM(CASE rd.result WHEN $cats::st_accepted THEN 1 ELSE 0 END) AS passed_count,
            SUM(CASE rd.result WHEN $cats::st_accepted THEN 0 ELSE 1 END) AS failed_count,
            rd.test_rank
        FROM reqs r
            INNER JOIN req_details rd ON rd.req_id = r.id
            INNER JOIN contest_accounts ca ON
                ca.contest_id = r.contest_id AND ca.account_id = r.account_id
        WHERE
            r.problem_id = ? AND r.contest_id = ? AND ca.is_jury = 0
        GROUP BY rd.test_rank~, 'test_rank', { Slice => {} },
        $pid, $cid) or return;

    my $c = $dbh->selectall_arrayref(qq~
        SELECT COUNT(*) AS cnt, rd1.test_rank AS r1, rd2.test_rank AS r2
            FROM reqs r
            INNER JOIN req_details rd1 ON rd1.req_id = r.id
            INNER JOIN req_details rd2 ON rd2.req_id = r.id
            INNER JOIN contest_accounts ca ON
                ca.contest_id = r.contest_id AND ca.account_id = r.account_id
            WHERE
                rd1.test_rank <> rd2.test_rank AND
                rd1.result = $cats::st_accepted AND
                rd2.result <> $cats::st_accepted AND
                r.problem_id = ? AND r.contest_id = ? AND ca.is_jury = 0
            GROUP BY rd1.test_rank, rd2.test_rank~, { Slice => {} },
        $pid, $cid);

    my $h = {};
    $h->{$_->{r1}}->{$_->{r2}} = $_->{cnt} for @$c;
    my $size = max(keys %$totals) || 0;
    my $cm = [
        map {
            my $hr = $h->{$_} || {};
            { data => [ map {{ n => ($hr->{$_} || 0) }} 1..$size ], %{$totals->{$_} || {}} }
        } 1..$size
    ];

    my (@equiv_tests, @simple_tests, @hard_tests);
    for my $i (1..$size)
    {
        my ($too_simple, $too_hard) = (1, 1);
        for my $j (1..$size)
        {
            my $zij = !exists $h->{$i} || !exists $h->{$i}->{$j};
            my $zji = !exists $h->{$j} || !exists $h->{$j}->{$i};
            push @equiv_tests, { t1 => $i, t2 => $j } if $zij && $zji && $j > $i;
            $too_simple &&= $zji;
            $too_hard &&= $zij;
        }
        push @simple_tests, { t => $i } if $too_simple;
        push @hard_tests, { t => $i } if $too_hard;
    }

    $t->param(
        comparision_matrix => $cm,
        equiv_lists => greedy_cliques(@equiv_tests),
        simple_tests => \@simple_tests,
        hard_tests => \@hard_tests,
    );
}


# Администратор добавляет нового пользователя в текущий турнир.
sub users_new_save
{
    $is_jury or return;
    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->insert($cid) or return;
}


sub users_edit_frame 
{      
    init_template('main_users_edit.htm');

    my $id = url_param('edit') or return;
    my $u = CATS::User->new->load($id) or return;
    $t->param(
        %$u, id => $id, countries => \@cats::countries, is_root => $is_root,
        href_action => url_f('users'),
        href_impersonate => url_f('users', impersonate => $id));
}


sub users_edit_save
{
    my $u = CATS::User->new->parse_params;
    my $set_password = param_on('set_password');
    my $id = param('id');

    $u->validate_params(
        validate_password => $set_password, id => $id,
        # Здесь недостаточно просто is_jury, поскольку можно зарегистрировать
        # любую команду в свой турнир и потом переименовать.
        # Надо требовать is_jury во всех официальных соревнованиях,
        # где участвовала команда, но проще просто проверить is_root.
        allow_official_rename => $is_root)
        or return;

    $u->{passwd} = $u->{password1} if $set_password;
    delete @$u{qw(password1 password2)};
    $dbh->do(_u $sql->update('accounts', { %$u }, { id => $id }));
    $dbh->commit;
}


sub registration_frame
{
    init_template('main_registration.htm');

    $t->param(countries => [ @cats::countries ], href_login => url_f('login'));

    defined param('register')
        or return;
    
    my $u = CATS::User->new->parse_params;
    $u->validate_params(validate_password => 1) or return;
    $u->insert or return;
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


sub settings_frame
{
    init_template('main_settings.htm');
    $settings = {} if defined param('clear') && $is_team;
    settings_save if defined param('edit_save') && $is_team;

    $uid or return;
    my $u = CATS::User->new->load($uid) or return;
    $t->param(
        countries => \@cats::countries, href_action => url_f('users'),
        title_suffix => res_str(518), %$u);
    if ($is_root)
    {
        my $d = Data::Dumper->new([ $settings ]);
        $d->Quotekeys(0);
        $d->Sortkeys(1);
        $t->param(settings => $d->Dump);
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
    print redirect(-uri => url_function('contests', sid => $sid));
    -1;
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
        'users', 'main_users.' . (param('json') ? 'json' : 'htm'));

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
        @cols = ( { caption => res_str(616), order_by => '4', width => '15%' } );
    }

    push @cols,
        { caption => res_str(608), order_by => '5', width => '20%' },
        { caption => res_str(629), order_by => '12', width => '5%' };

    if ($is_jury)
    {
        push @cols,
            (
              { caption => res_str(611), order_by => '6', width => '10%' },
              { caption => res_str(612), order_by => '7', width => '10%' },
              { caption => res_str(613), order_by => '8', width => '10%' },
              { caption => res_str(614), order_by => '9', width => '10%' } );
    }

    push @cols, (
        { caption => res_str(607), order_by => '3', width => '10%' },
        { caption => res_str(609), order_by => '13', width => '10%' },
        { caption => res_str(632), order_by => '10', width => '10%' } );

    define_columns(url_f('users'), $is_jury ? 3 : 2, 1, \@cols);

    return if !$is_jury && param('json') && $contest->is_practice;

    my $fields =
        'A.id, CA.id, A.country, A.login, A.team_name, ' . 
        'CA.is_jury, CA.is_ooc, CA.is_remote, CA.is_hidden, CA.is_virtual, A.motto, CA.tag';
    my $sql = sprintf qq~
        SELECT $fields, COUNT(DISTINCT R.problem_id)
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
            $aid, $caid, $country_abb, $login, $team_name, $jury,
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
            login => $login,
            editable => $is_jury,
            messages => $is_jury,
            team_name => $team_name,
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
            submenu => [ { href_item => url_f('users', new => 1), item_name => res_str(541) } ],
            editable => 1
        );
    }

    $c->finish;
}


sub user_stats_frame
{
    init_template('main_user_stats.htm');
    my $uid = param('uid') or return;
    my $u = $dbh->selectrow_hashref(q~
        SELECT A.*, last_login AS last_login_date
        FROM accounts A WHERE A.id = ?~, { Slice => {} }, $uid) or return;
    my $contests = $dbh->selectall_arrayref(qq~
        SELECT C.id, C.title, C.start_date + CA.diff_time AS start_date,
            (SELECT COUNT(DISTINCT R.problem_id) FROM reqs R
                WHERE R.contest_id = C.id AND R.account_id = CA.account_id AND R.state = $cats::st_accepted
            ) AS accepted_count,
            (SELECT COUNT(*) FROM contest_problems CP
                WHERE CP.contest_id = C.id AND CP.status < $cats::problem_st_hidden
            ) AS problem_count
        FROM contests C INNER JOIN contest_accounts CA ON CA.contest_id = C.id
        WHERE
            CA.account_id = ? AND C.ctype = 0 AND C.is_hidden = 0 AND
            CA.is_hidden = 0 AND C.defreeze_date < CURRENT_TIMESTAMP
        ORDER BY C.start_date + CA.diff_time DESC~,
        { Slice => {} }, $uid);
    my $pr = sub { url_f(
        'console', uf => $uid, i_value => -1, se => 'user_stats', search => $_[0], rows => 30
    ) };
    $t->param(
        %$u, contests => $contests, is_root => $is_root,
        href_all_problems => $pr->(''),
        href_solved_problems => $pr->('accepted=1'),
        title_suffix => $u->{team_name},
    );
}


sub reference_names()
{
    (
        { name => 'compilers', new => 542, item => 517 },
        { name => 'judges', new => 543, item => 511 },
        { name => 'keywords', new => 550, item => 549 },
        { name => 'import_sources', item => 557 },
    )
}


sub references_menu
{
    my ($ref_name) = @_;

    my @result;
    for (reference_names())
    {
        my $sel = $_->{name} eq $ref_name;
        push @result,
            { href_item => url_f($_->{name}), item_name => res_str($_->{item}), selected => $sel };
        if ($sel && $is_root && $_->{new})
        {
            unshift @result, 
                { href_item => url_f($_->{name}, new => 1), item_name => res_str($_->{new}) };
        }
    }
    @result;
}


sub compilers_new_frame
{
    init_template('main_compilers_new.htm');
    $t->param(href_action => url_f('compilers'));
}


sub compilers_new_save
{
    my $code = param('code');
    my $description = param('description');
    my $supported_ext = param('supported_ext');
    my $locked = param_on('locked');
    my $memory_handicap = param('memory_handicap');
    my $syntax = param('syntax');
            
    $dbh->do(qq~
        INSERT INTO default_de(id, code, description, file_ext, in_contests, memory_handicap, syntax)
        VALUES(?,?,?,?,?,?,?)~, {}, 
        new_id, $code, $description, $supported_ext, !$locked, $memory_handicap, $syntax);
    $dbh->commit;   
}


sub compilers_edit_frame
{
    init_template('main_compilers_edit.htm');

    my $id = url_param('edit');

    my ($code, $description, $supported_ext, $in_contests, $memory_handicap, $syntax) =
        $dbh->selectrow_array(qq~
            SELECT code, description, file_ext, in_contests, memory_handicap, syntax
            FROM default_de WHERE id = ?~, {},
            $id);

    $t->param(
        id => $id,
        code => $code, 
        description => $description, 
        supported_ext => $supported_ext, 
        locked => !$in_contests,
        memory_handicap => $memory_handicap,
        syntax => $syntax,
        href_action => url_f('compilers'));
}


sub compilers_edit_save
{
    my $code = param('code');
    my $description = param('description');
    my $supported_ext = param('supported_ext');
    my $locked = param_on('locked');
    my $memory_handicap = param('memory_handicap');
    my $syntax = param('syntax');
    my $id = param('id');

    $dbh->do(qq~
        UPDATE default_de
        SET code = ?, description = ?, file_ext = ?, in_contests = ?,
            memory_handicap = ?, syntax = ?
        WHERE id = ?~, {}, 
        $code, $description, $supported_ext, !$locked, $memory_handicap, $syntax, $id);
    $dbh->commit;
}


sub compilers_frame
{    
    if ($is_jury)
    {
        if ($is_root && defined url_param('delete')) # extra security
        {
            my $deid = url_param('delete');
            $dbh->do(qq~DELETE FROM default_de WHERE id=?~, {}, $deid);
            $dbh->commit;       
        }
        
        defined url_param('new') and return compilers_new_frame;
        defined url_param('edit') and return compilers_edit_frame;
    }

    init_listview_template('compilers', 'compilers', 'main_compilers.htm');

    if ($is_jury)
    {
        defined param('new_save') and compilers_new_save;
        defined param('edit_save') and compilers_edit_save;
    }

    define_columns(url_f('compilers'), 0, 0, [
        { caption => res_str(619), order_by => '2', width => '10%' },
        { caption => res_str(620), order_by => '3', width => '40%' },
        { caption => res_str(621), order_by => '4', width => '20%' },
        { caption => res_str(640), order_by => '6', width => '15%' },
        { caption => 'syntax' || res_str(621), order_by => '7', width => '10%' },
        ($is_jury ? { caption => res_str(622), order_by => '5', width => '10%' } : ())
    ]);

    my $where = $is_jury ? '' : ' WHERE in_contests = 1';
    my $c = $dbh->prepare(qq~
        SELECT id, code, description, file_ext, in_contests, memory_handicap, syntax
        FROM default_de$where ~.order_by);
    $c->execute;

    my $fetch_record = sub($)
    {            
        my ($did, $code, $description, $supported_ext, $in_contests, $memory_handicap, $syntax) =
            $_[0]->fetchrow_array
            or return ();
        return ( 
            editable => $is_root, did => $did, code => $code, 
            description => $description,
            supported_ext => $supported_ext,
            memory_handicap => $memory_handicap,
            syntax => $syntax,
            locked => !$in_contests,
            href_edit => url_f('compilers', edit => $did),
            href_delete => url_f('compilers', 'delete' => $did));
    };
    attach_listview(url_f('compilers'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('compilers') ], editable => $is_root)
        if ($is_jury);
}


sub judges_new_frame
{
    init_template('main_judges_new.htm');
    $t->param(href_action => url_f('judges'));
}


sub judges_new_save
{
    my $judge_name = param('judge_name');
    my $locked = param_on('locked');
    
    $judge_name ne '' && length $judge_name <= 20
        or return msg(5);
    
    $dbh->do(qq~
        INSERT INTO judges (
            id, nick, accept_contests, accept_trainings, lock_counter, is_alive, alive_date
        ) VALUES (?, ?, 1, 1, ?, 0, CURRENT_TIMESTAMP)~, {}, 
        new_id, $judge_name, $locked ? -1 : 0);
    $dbh->commit;
}


sub judges_edit_frame
{
    init_template('main_judges_edit.htm');

    my $jid = url_param('edit');
    my ($judge_name, $lock_counter) = $dbh->selectrow_array(qq~
        SELECT nick, lock_counter FROM judges WHERE id=?~, {}, $jid);
    $t->param(id => $jid, judge_name => $judge_name, locked => $lock_counter, href_action => url_f('judges'));
}


sub judges_edit_save
{
    my $jid = param('id');
    my $judge_name = param('judge_name') || '';
    my $locked = param_on('locked');
    
    $judge_name ne '' && length $judge_name <= 20
        or return msg(5);
  
    $dbh->do(qq~
        UPDATE judges SET nick = ?, lock_counter = ? WHERE id = ?~, {},
        $judge_name, $locked ? -1 : 0, $jid);
    $dbh->commit;
}


sub judges_frame 
{
    $is_jury or return;
 
    if (defined url_param('delete'))
    {
        my $jid = url_param('delete');
        $dbh->do(qq~DELETE FROM judges WHERE id=?~, {}, $jid);
        $dbh->commit;
    }

    $is_root && defined url_param('new') and return judges_new_frame;
    $is_root && defined url_param('edit') and return judges_edit_frame;

    init_listview_template('judges', 'judges', 'main_judges.htm');

    $is_root && defined param('new_save') and judges_new_save;
    $is_root && defined param('edit_save') and judges_edit_save;

    define_columns(url_f('judges'), 0, 0, [
        { caption => res_str(625), order_by => '2', width => '65%' },
        { caption => res_str(626), order_by => '3', width => '10%' },
        { caption => res_str(633), order_by => '4', width => '15%' },
        { caption => res_str(627), order_by => '5', width => '10%' }
    ]);

    my $c = $dbh->prepare(qq~
        SELECT id, nick, is_alive, alive_date, lock_counter
            FROM judges ~.order_by);
    $c->execute;

    my $fetch_record = sub($)
    {            
        my ($jid, $judge_name, $is_alive, $alive_date, $lock_counter) = $_[0]->fetchrow_array
            or return ();
        return ( 
            editable => $is_root,
            jid => $jid, judge_name => $judge_name, 
            locked => $lock_counter,
            is_alive => $is_alive,
            alive_date => $alive_date,
            href_edit=> url_f('judges', edit => $jid),
            href_delete => url_f('judges', 'delete' => $jid)
        );
    };
             
    attach_listview(url_f('judges'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('judges') ], editable => 1);
    
    my ($not_processed) = $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM reqs WHERE state = ?~, undef,
        $cats::st_not_processed);
    $t->param(not_processed => $not_processed);
    
    $dbh->do(qq~
        UPDATE judges SET is_alive = 0, alive_date = CURRENT_TIMESTAMP WHERE is_alive = 1~);
    $dbh->commit;
}


sub keywords_fields () { qw(name_ru name_en code) }


sub keywords_new_frame
{
    init_template('main_keywords_new.htm');
    $t->param(href_action => url_f('keywords'));
}


sub keywords_new_save
{
    my %p = map { $_ => (param($_) || '') } keywords_fields();
    
    $p{name_en} ne '' && 0 == grep length $p{$_} > 200, keywords_fields()
        or return msg(84);
    
    my $field_names = join ', ', keywords_fields();
    $dbh->do(qq~
        INSERT INTO keywords (id, $field_names) VALUES (?, ?, ?, ?)~, {}, 
        new_id, @p{keywords_fields()});
    $dbh->commit;
}


sub keywords_edit_frame
{
    init_template('main_keywords_edit.htm');

    my $kwid = url_param('edit');
    my $kw = $dbh->selectrow_hashref(qq~SELECT * FROM keywords WHERE id=?~, {}, $kwid);
    $t->param(%$kw, href_action => url_f('keywords'));
}


sub keywords_edit_save
{
    my $kwid = param('id');
    my %p = map { $_ => (param($_) || '') } keywords_fields();

    $p{name_en} ne '' && 0 == grep(length $p{$_} > 200, keywords_fields())
        or return msg(84);

    my $set = join ', ', map "$_ = ?", keywords_fields();
    $dbh->do(qq~
        UPDATE keywords SET $set WHERE id = ?~, {}, 
        @p{keywords_fields()}, $kwid);
    $dbh->commit;
}


sub keywords_frame
{
    if ($is_root)
    {
        if (defined url_param('delete'))
        {
            my $kwid = url_param('delete');
            $dbh->do(qq~DELETE FROM keywords WHERE id = ?~, {}, $kwid);
            $dbh->commit;
        }

        defined url_param('new') and return keywords_new_frame;
        defined url_param('edit') and return keywords_edit_frame;
    }
    init_listview_template('keywords', 'keywords', 'main_keywords.htm');

    $is_root && defined param('new_save') and keywords_new_save;
    $is_root && defined param('edit_save') and keywords_edit_save;

    define_columns(url_f('keywords'), 0, 0, [
        { caption => res_str(638), order_by => '2', width => '31%' },
        { caption => res_str(636), order_by => '3', width => '31%' },
        { caption => res_str(637), order_by => '4', width => '31%' },
    ]);

    my $c = $dbh->prepare(qq~
        SELECT id, code, name_ru, name_en FROM keywords ~.order_by);
    $c->execute;

    my $fetch_record = sub($)
    {
        my ($kwid, $code, $name_ru, $name_en) = $_[0]->fetchrow_array
            or return ();
        return ( 
            editable => $is_root,
            kwid => $kwid, code => $code, name_ru => $name_ru, name_en => $name_en,
            href_edit=> url_f('keywords', edit => $kwid),
            href_delete => url_f('keywords', 'delete' => $kwid),
            href_view_problems => url_f('problems', kw => $kwid),
        );
    };

    attach_listview(url_f('keywords'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('keywords') ], editable => $is_root) if $is_jury;
}


sub import_sources_frame
{
    init_listview_template('import_sources', 'import_sources', 'main_import_sources.htm');
    define_columns(url_f('import_sources'), 0, 0, [
        { caption => res_str(638), order_by => '2', width => '30%' },
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
    my ($fname, $src) = $dbh->selectrow_array(qq~
        SELECT fname, src FROM problem_sources WHERE id = ? AND guid IS NOT NULL~, undef, $psid) or return;
    binmode(STDOUT, ':raw');
    print STDOUT CGI::header(
        -type => 'text/plain',
        -content_disposition => "inline;filename=$fname");
    print STDOUT $src;
}


sub send_message_box_frame
{
    init_template('main_send_message_box.htm');
    return unless $is_jury;

    my $caid = url_param('caid');

    my $aid = $dbh->selectrow_array(qq~SELECT account_id FROM contest_accounts WHERE id=?~, {}, $caid);
    my $team = $dbh->selectrow_array(qq~SELECT team_name FROM accounts WHERE id=?~, {}, $aid);

    $t->param(team => $team);

    if (defined param('send'))
    {
        my $message_text = param('message_text');

        my $s = $dbh->prepare(qq~
            INSERT INTO messages (id, send_time, text, account_id, received)
                VALUES (?, CURRENT_TIMESTAMP, ?, ?, 0)~);
        $s->bind_param(1, new_id);
        $s->bind_param(2, $message_text, { ora_type => 113 });
        $s->bind_param(3, $caid);
        $s->execute;
        $dbh->commit;
        $t->param(sent => 1);
    }
}


sub answer_box_frame
{
    init_template('main_answer_box.htm');

    my $qid = url_param('qid');

    my $r = $dbh->selectrow_hashref(qq~
        SELECT
            Q.account_id AS caid, CA.account_id AS aid, A.login, A.team_name,
            Q.submit_time, Q.question, Q.clarified, Q.answer
        FROM questions Q
            INNER JOIN contest_accounts CA ON CA.id = Q.account_id
            INNER JOIN accounts A ON A.id = CA.account_id
        WHERE Q.id = ?~, { Slice => {} },
        $qid);

    $t->param(team_name => $r->{team_name});

    if (defined param('clarify') && (my $a = param('answer_text')))
    {
        $r->{answer} ||= '';
        $r->{answer} .= " $a";

        my $s = $dbh->prepare(qq~
            UPDATE questions
                SET clarification_time = CURRENT_TIMESTAMP, answer = ?, received = 0, clarified = 1
                WHERE id = ?~);
        $s->bind_param(1, $r->{answer}, { ora_type => 113 } );
        $s->bind_param(2, $qid);
        $s->execute;
        $dbh->commit;
        $t->param(clarified => 1);
    }
    else
    {
        $t->param(
            submit_time => $r->{submit_time},
            question_text => $r->{question},
            answer => $r->{answer});
    }
}


sub source_encodings { {'UTF-8' => 1, 'WINDOWS-1251' => 1, 'KOI8-R' => 1, 'CP866' => 1, 'UCS-2LE' => 1} }

sub source_links
{
    my ($si, $is_jury) = @_;
    my ($current_link) = url_param('f') || '';
    
    $si->{href_contest} =
        url_function('problems', cid => $si->{contest_id}, sid => $sid);
    $si->{href_problem} =
        url_function('problem_text', cpid => $si->{cp_id}, cid => $si->{contest_id}, sid => $sid);
    for (qw/run_details view_source run_log download_source/)
    {
        $si->{"href_$_"} = url_f($_, rid => $si->{req_id});
        $si->{"href_class_$_"} = $_ eq $current_link ? 'current_link' : '';
    }
    $si->{is_jury} = $is_jury;
    $t->param(is_jury => $is_jury);
    if ($is_jury && $si->{judge_id})
    {
        $si->{judge_name} = get_judge_name($si->{judge_id});
    }
    my $se = param('src_enc') || param('comment_enc') || 'WINDOWS-1251';
    $t->param(source_encodings =>
        [ map {{ enc => $_, selected => $_ eq $se }} sort keys %{source_encodings()} ]);
}


sub get_run_info
{
    my ($contest, $rid) = @_;
    my $points = $contest->{points};

    my %run_details;
    my $rd_fields = join ', ', (
         qw(test_rank result),
         ($contest->{show_test_resources} ? qw(time_used memory_used disk_used) : ()),
         ($contest->{show_checker_comment} ? qw(checker_comment) : ()),
    );

    my $c = $dbh->prepare(qq~
        SELECT $rd_fields FROM req_details WHERE req_id = ? ORDER BY test_rank~);
    $c->execute($rid);
    my $last_test = 0;
    my $total_points = 0;
    
    while (my $row = $c->fetchrow_hashref())
    {
        # На случай, если в БД не well-formed utf8
        if ($contest->{show_checker_comment})
        {
            my $d = $row->{checker_comment} || '';
            my $enc = param('comment_enc') || '';
            source_encodings()->{$enc} or $enc = 'UTF-8';
            $row->{checker_comment} = Encode::decode($enc, $d, Encode::FB_QUIET);
            $row->{checker_comment} .= '...' if $d ne '';
        }
        
        my $prev_test = $last_test;
        my $accepted = $row->{result} == $cats::st_accepted;
        my $p = $accepted ? $points->[$row->{test_rank} - 1] : 0;
        $run_details{$last_test = $row->{test_rank}} =
        {
            state_to_display($row->{result}),
            map({ $_ => $contest->{$_} }
                qw(show_test_resources show_checker_comment)),
            %$row, show_points => $contest->{show_points}, points => $p,
        };
        $total_points += ($p || 0);
        # Тесты запускаются в случайном порядке.
        # Если участник просмотрит таблицу результатов в процессе тестирования решения,
        # он может увидеть результат 'OK' для теста с номером, бОльшим, чем первый
        # не прошедший тест. Поэтому вывод результатов прекращаем на первом
        # не прошедшем ИЛИ не ещё запущенном тесте.
        last if
            !$contest->{show_all_tests} &&
            (!$accepted || $prev_test != $last_test - 1); 
    }
    # Выводить 'not processed' для тестов, которые вообще не запускались.
    if ($contest->{show_all_tests} && !$contest->{run_all_tests})
    {
        $last_test = @$points;
    }
    my %testset;
    @testset{CATS::Testset::get_testset($rid)} = undef;
    
    my $run_row = sub {
        my ($rank) = @_;
        return $run_details{$rank} if exists $run_details{$rank};
        return () unless $contest->{show_all_tests};
        my %r = ( test_rank => $rank );
        $r{exists $testset{$rank} ? 'not_processed' : 'not_in_testset'} = 1;
        return \%r;
    };
    return {
        %$contest,
        total_points => $total_points,
        run_details => [ map $run_row->($_), 1..$last_test ]
    };
}


sub get_contest_info
{
    my ($si, $jury_view) = @_;

    my $contest = $dbh->selectrow_hashref(qq~
        SELECT
            id, run_all_tests, show_all_tests, show_test_resources,
            show_checker_comment
            FROM contests WHERE id = ?~, { Slice => {} },
        $si->{contest_id});

    $contest->{$_} ||= $jury_view
        for qw(show_all_tests show_test_resources show_checker_comment);

    my $p = $contest->{points} =
        $contest->{show_all_tests} ?
        $dbh->selectcol_arrayref(qq~
            SELECT points FROM tests WHERE problem_id = ? ORDER BY rank~, {},
            $si->{problem_id})
        : [];
    $contest->{show_points} = 0 != grep defined $_ && $_ > 0, @$p;
    $contest;
}


sub get_log_dump
{
    my ($rid, $compile_error) = @_;
    my ($dump) = $dbh->selectrow_array(qq~
        SELECT dump FROM log_dumps WHERE req_id = ?~, {},
        $rid) or return ();
    $dump = Encode::decode('CP1251', $dump);
    $dump =~ s/(?:.|\n)+spawner\\sp\s((?:.|\n)+)compilation error\n/$1/m
        if $compile_error;
    return (judge_log_dump => $dump);
}


sub run_details_frame
{
    init_template('main_run_details.htm');

    my $rid = url_param('rid') or return;
    my $rids = [ grep /^\d+$/, split /,/, $rid ];
    my $si = get_sources_info(request_id => $rids) or return;
    
    my @runs;
    my ($is_jury, $contest) = (0, { id => 0 });
    for (@$si)
    {
        $is_jury = is_jury_in_contest(contest_id => $_->{contest_id})
            if $_->{contest_id} != $contest->{id};
        $is_jury || $uid == $_->{account_id} or next;

        if ($is_jury && param('retest'))
        {
            enforce_request_state(
                request_id => $_->{req_id},
                state => $cats::st_not_processed,
                testsets => param('testsets'));
            $_ = get_sources_info(request_id => $_->{req_id}) or next;
        }

        source_links($_, $is_jury);
        $contest = get_contest_info($_, $is_jury && !url_param('as_user'))
            if $_->{contest_id} != $contest->{id};
        push @runs,
            $_->{state} == $cats::st_compilation_error ?
            { get_log_dump($_->{req_id}, 1) } : get_run_info($contest, $_->{req_id});
    }
    $t->param(sources_info => $si, runs => \@runs);
}


sub prepare_source
{
    my ($show_msg) = @_;
    my $rid = url_param('rid') or return;

    my $sources_info = get_sources_info(request_id => $rid, get_source => 1)
        or return;

    my $is_jury = is_jury_in_contest(contest_id => $sources_info->{contest_id});
    $is_jury || $sources_info->{account_id} == ($uid || 0)
        or return ($show_msg && msg(126));
    my $se = param('src_enc') || 'WINDOWS-1251';
    if ($se && source_encodings()->{$se} && $sources_info->{file_name} !~ m/\.zip$/)
    {
        Encode::from_to($sources_info->{src}, $se, 'utf-8');
    }
    ($sources_info, $is_jury);
}


sub view_source_frame
{
    init_template('main_view_source.htm');
    my ($sources_info, $is_jury) = prepare_source(1);
    $sources_info or return;
    if ($is_jury && (my $file = param('replace_source')))
    {
        my $src = upload_source($file) or return;
        my $s = $dbh->prepare(q~
            UPDATE sources SET src = ? WHERE req_id = ?~);
        $s->bind_param(1, $src, { ora_type => 113 } ); # blob
        $s->bind_param(2, $sources_info->{req_id} );
        $s->execute;
        $dbh->commit;
        $sources_info->{src} = $src;
    }
    if ($sources_info->{file_name} =~ m/\.zip$/) {
        $sources_info->{src} = sprintf 'ZIP, %d bytes', length ($sources_info->{src});
    }
    source_links($sources_info, $is_jury);
    /^[a-z]+$/i and $sources_info->{syntax} = $_ for param('syntax');
    $sources_info->{src_lines} = [ map {}, split("\n", $sources_info->{src}) ];
    $t->param(sources_info => [ $sources_info ]);
}


sub download_source_frame
{
    my ($si, $is_jury) = prepare_source(0);
    unless ($si)
    {
        init_template('main_view_source.htm');
        return;
    }

    $si->{file_name} =~ m/\.([^.]+)$/;
    my $ext = $1 || 'unknown';
    binmode(STDOUT, ':raw');
    print STDOUT CGI::header(
        -type => ($ext eq 'zip' ? 'application/zip' : 'text/plain'),
        -content_disposition => "inline;filename=$si->{req_id}.$ext");
    print STDOUT $si->{src};
}


sub try_set_state
{
    my ($si, $rid) = @_;
    defined param('set_state') or return;
    my $state = 
    {       
        not_processed =>         $cats::st_not_processed,
        accepted =>              $cats::st_accepted,
        wrong_answer =>          $cats::st_wrong_answer,
        presentation_error =>    $cats::st_presentation_error,
        time_limit_exceeded =>   $cats::st_time_limit_exceeded,
        memory_limit_exceeded => $cats::st_memory_limit_exceeded,            
        runtime_error =>         $cats::st_runtime_error,
        compilation_error =>     $cats::st_compilation_error,
        security_violation =>    $cats::st_security_violation,
        ignore_submit =>         $cats::st_ignore_submit,
    }->{param('state')};
    defined $state or return;

    my $failed_test = sprintf '%d', param('failed_test') || '0';
    enforce_request_state(
        request_id => $rid, failed_test => $failed_test, state => $state);
    my %st = state_to_display($state);
    while (my ($k, $v) = each %st)
    {
        $si->{$k} = $v;
    }
    $si->{failed_test} = $failed_test;
    1;
}


sub run_log_frame
{
    init_template('main_run_log.htm');
    my $rid = url_param('rid') or return;

    # HACK: Чтобы избежать лишнего обращения к БД, требуем, чтобы
    # пользователь являлся членом жюри не только соревнования,
    # в котором просматривает задачу, но и своего текущего соревнования.
    $is_jury or return; 

    my $si = get_sources_info(request_id => $rid)
        or return;
    is_jury_in_contest(contest_id => $si->{contest_id})
        or return;

    # перечитать параметры задачи, если обновилось её состояние
    $si = get_sources_info(request_id => $rid)
        if try_set_state($si, $rid);
    $t->param(sources_info => [$si]);

    source_links($si, 1);
    $t->param(get_log_dump($rid));

    my $tests = $dbh->selectcol_arrayref(qq~
        SELECT rank FROM tests WHERE problem_id = ? ORDER BY rank~, {},
        $si->{problem_id});
    $t->param(tests => [ map {test_index => $_}, @$tests ]);
}


sub diff_runs_frame
{
    init_template('main_diff_runs.htm');
    $is_jury or return;
    
    my $si = get_sources_info(
        request_id => [ param('r1'), param('r2') ],
        get_source => 1
    ) or return;
    @$si == 2 or return;

    # Пользователь должен входить в жюри турниров, которым принадлежат обе задачи.
    # Если задачи принадлежат одному и тому же турниру, проверяем его только однажды.
    my ($cid1, $cid2) = map $_->{contest_id}, @$si;
    is_jury_in_contest(contest_id => $cid1)
        or return;
    $cid1 == $cid2 || is_jury_in_contest(contest_id => $cid2)
        or return;

    source_links($_, 1) for @$si;
    
    for my $info (@$si)
    {
        $info->{lines} = [split "\n", $info->{src}];
        s/\s*$// for @{$info->{lines}};
    }
    
    my @diff = ();

    my $SL = sub { $si->[$_[0]]->{lines}->[$_[1]] || '' }; 
    
    my $match = sub { push @diff, escape_html($SL->(0, $_[0])) . "\n"; };
    my $only_a = sub { push @diff, span({class=>'diff_only_a'}, escape_html($SL->(0, $_[0])) . "\n"); };
    my $only_b = sub { push @diff, span({class=>'diff_only_b'}, escape_html($SL->(1, $_[1])) . "\n"); };

    Algorithm::Diff::traverse_sequences(
        $si->[0]->{lines},
        $si->[1]->{lines},
        {
            MATCH     => $match,     # callback on identical lines
            DISCARD_A => $only_a,    # callback on A-only
            DISCARD_B => $only_b,    # callback on B-only
        }
    );

    $t->param(
        sources_info => $si,
        diff_lines => [map {line => $_}, @diff]
    );
}


sub rank_table
{
    my $template_name = shift;
    init_template('main_rank_table_content.htm');
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
    init_template('main_rank_table.htm');

    my $rt = CATS::RankTable->new;
    $rt->get_contest_list_param;
    $rt->get_contests_info($uid);
    $contest->{title} = $rt->{title};

    my @params = (
        hide_ooc => $hide_ooc, hide_virtual => $hide_virtual, cache => $cache,
        clist => $rt->{contest_list}, points => $show_points,
        filter => Encode::decode_utf8(url_param('filter') || undef),
    );
    $t->param(href_rank_table_content => url_f('rank_table_content', @params));
    my $submenu =
        [ { href_item => url_f('rank_table_content', @params, printable => 1), item_name => res_str(552) } ];
    if ($is_jury)
    {
        push @$submenu,
            { href_item => url_f('rank_table', @params, cache => 1 - ($cache || 0)), item_name => res_str(553) },
            { href_item => url_f('rank_table', @params, points => 1 - ($show_points || 0)), item_name => res_str(554) };
    }
    $t->param(submenu => $submenu, title_suffix => res_str(529));
}


sub rank_table_content_frame
{
    rank_table('main_rank_table_iframe.htm');  
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


sub russian ($)
{
    Encode::decode('KOI8-R', $_[0]);
}


sub check_spelling
{
    my ($word) = @_;
    # символ _ приводит к SIGSEGV (!) внутри ASpell
    return $word if $word =~ /(?:\d|_)/;
    my $koi = Encode::encode('KOI8-R', $word);
    {
        no encoding;
        $koi =~ s/ё/е/g;
        use encoding 'utf8', STDIN => undef;
    }
    return $word if $spellchecker->check($koi);
    my $suggestion = join ' | ', grep $_, (map russian($_), $spellchecker->suggest($koi))[0..9];
    return qq~<a class="spell" title="$suggestion">$word</a>~;
}


sub process_text
{
    if ($spellchecker)
    {
        my @tex_parts = split /\$/, $text_span;
        my $i = 1;
        for (@tex_parts)
        {
            $i = !$i;
            next if $i;
            # игнорировать entities, учитывать апострофы как часть слов, первый символ должен быть буквой
            s/(?<!(?:\w|&))(\w(?:\w|\')*)/check_spelling($1)/eg;
        }
        $html_code .= join '$', @tex_parts;
        # split игнорирует разделитель в конце строки, m// игнорирует \n в конце строки, поэтому \z
        $html_code .= '$' if $text_span =~ /\$\z/s;
    }
    else
    {
        $html_code .= $text_span;
    }
    $text_span = '';
}


# генерация страницы с текстом задач
sub start_element
{
    my ($el, %atts) = @_;

    process_text;
    $html_code .= "<$el";
    for my $name (keys %atts)
    {
        my $attrib = $atts{$name};
        $html_code .= qq~ $name="$attrib"~;
    }
    $html_code .= '>';
}


sub end_element
{
    my ($el) = @_;
    process_text;
    $html_code .= "</$el>";
}


sub ch_1
{
    my ($p, $text) = @_;
    # Склеиваем подряд идущие текстовые элементы, и потом обрабатываем их все вместе
    $text_span .= $text;
}


# если задача ещё ни разу не скачивалась, сгенерировать для неё хеш
sub ensure_problem_hash
{
    my ($problem_id, $hash) = @_;
    return 1 if $$hash;
    my @ch = ('a'..'z', 'A'..'Z', '0'..'9');
    $$hash = join '', map @ch[rand @ch], 1..32;
    #$$hash = mktemp('X' x 32);
    $dbh->do(qq~UPDATE problems SET hash = ? WHERE id = ?~, undef, $$hash, $problem_id);
    $dbh->commit;
    return 0;
}


sub download_image
{
    my ($name) = @_;
    # полагаем, что картинки относительно маленькие (единицы Кб), поэтому эффективнее
    # вытаскивать их одним запросом вместе с хешем задачи
    my ($pic, $ext, $hash) = $dbh->selectrow_array(qq~
        SELECT c.pic, c.extension, p.hash FROM pictures c
        INNER JOIN problems p ON c.problem_id = p.id
        WHERE p.id = ? AND c.name = ?~, {}, $current_pid, $name);
    ensure_problem_hash($current_pid, \$hash);
    return 'unknown' if !$name;
    $ext ||= '';
    # секьюрити. это может привести к дублированию картинок, например, с именами pic1 и pic.1
    $name =~ tr/a-zA-Z0-9_//cd;
    $ext =~ tr/a-zA-Z0-9_//cd;
    my $fname = "./download/img/img_${hash}_$name.$ext";
    -f cats_dir() . $fname or CATS::BinaryFile::save(cats_dir() . $fname, $pic);
    return $fname;
}


sub save_attachment
{
    my ($name) = @_;
    # полагаем, что вложенные файлы относительно маленькие (единицы Кб), поэтому эффективнее
    # вытаскивать их одним запросом вместе с хешем задачи
    my ($data, $file, $hash) = $dbh->selectrow_array(qq~
        SELECT pa.data, pa.file_name, p.hash FROM problem_attachments pa
        INNER JOIN problems p ON pa.problem_id = p.id
        WHERE p.id = ? AND pa.name = ?~, {}, $current_pid, $name);
    ensure_problem_hash($current_pid, \$hash);
    return 'unknown' if !$file;
    # секьюрити
    $file =~ tr/a-zA-Z0-9_.//cd;
    $file =~ s/\.+/\./g; # не более одной точки подряд
    my $fname = "./download/att/${hash}_$file";
    -f cats_dir() . $fname or CATS::BinaryFile::save(cats_dir() . $fname, $data);
    return $fname;
}


sub sh_1
{
    my ($p, $el, %atts) = @_;
    
    if ($el eq 'img' && $atts{picture})
    {
        $atts{src} = download_image($atts{picture});
        delete $atts{picture};
    }
    elsif ($el eq 'a' && $atts{attachment})
    {
        $atts{href} = save_attachment($atts{attachment});
        delete $atts{attachment};
    }
    elsif ($el eq 'object' && $atts{attachment})
    {
        $atts{data} = save_attachment($atts{attachment});
        delete $atts{attachment};
    }
    start_element($el, %atts);
}


sub eh_1
{
    my ($p, $el) = @_;
    end_element($el);
}


sub parse
{
    my $xml_patch = shift;
    my $parser = new XML::Parser::Expat;

    $html_code = '';

    $parser->setHandlers(
        'Start' => \&sh_1,
        'End'   => \&eh_1,
        'Char'  => \&ch_1);

    $parser->parse("<div>$xml_patch</div>");
    return $html_code;
}


sub contest_visible
{
    return (1, 1) if $is_jury;

    my $pid = url_param('pid');
    my $cpid = url_param('cpid');
    my $contest_id = url_param('cid') || $cid;

    my ($s, $t, $p) = ('', '', '');
    if (defined $pid)
    {
        $s = 'INNER JOIN problems P ON C.id = P.contest_id';
        $t = 'P';
        $p = $pid;
    }
    elsif (defined $cpid)
    {
        $s = 'INNER JOIN contest_problems CP ON C.id = CP.contest_id';
        $t = 'CP';
        $p = $cpid;
    }
    elsif (defined $contest_id) # Показать все задачи турнира.
    {
        $s = '';
        $t = 'C';
        $p = $contest_id;
    }    

    my $c = $dbh->selectrow_hashref(qq~
        SELECT
            CURRENT_TIMESTAMP - C.start_date AS since_start,
            C.local_only, C.id AS orig_cid, C.show_packages, C.is_hidden
            FROM contests C $s WHERE $t.id = ?~,
        undef, $p);
    if (($c->{since_start} || 0) > 0 && !$c->{is_hidden})
    {
        $c->{local_only} or return (1, $c->{show_packages});
        defined $uid or return (0, 0);
        # Должно быть локальное участие в основном турнире задачи
        # либо, если запрошены все задачи турнира, то в этом турнире.
        # Более полная проверка приводит к сложным условиям в составных турнирах.
        my ($is_remote) = $dbh->selectrow_array(q~
            SELECT is_remote FROM contest_accounts
            WHERE account_id = ? AND contest_id = ?~, {},
            $uid, $c->{orig_cid});
        return (1, $c->{show_packages}) if defined $is_remote && $is_remote == 0;
    }
    return (0, 0);
}    


sub problem_text_frame
{
    my ($show, $explain) = contest_visible();
    if (!$show)
    {
        die if $is_static_page; # В статическом режиме нельзя выводить меню
        init_template('main_access_denied.htm');
        return;
    }
    $explain = $explain && url_param('explain');

    init_template('main_problem_text.htm');

    my (@id_problems, @problems, %pcodes);
    
    my $pid = url_param('pid');
    my $cpid = url_param('cpid');
    my $show_points;

    if (defined $pid)
    {
        push @id_problems, $pid;
    }
    elsif (defined $cpid)
    {
        (my $problem_id, my $code, $show_points) = $dbh->selectrow_array(qq~
            SELECT CP.problem_id, CP.code, C.rules
            FROM contests C INNER JOIN contest_problems CP ON CP.contest_id = C.id
            WHERE CP.id = ?~, {},
            $cpid) or return;
        push @id_problems, $problem_id;
        $pcodes{$problem_id} = $code;
    }
    else # Показать все задачи турнира
    {
        ($show_points) = $contest->{rules};

        # Надо либо делать проверку на статическую страницу,
        # либо не выводить скрытые задачи даже жюри.
        my $c = $dbh->prepare(qq~
            SELECT problem_id, code FROM contest_problems
            WHERE contest_id = ? AND status < $cats::problem_st_hidden
            ORDER BY code~);
        $c->execute(url_param('cid') || $cid);
        while (my ($problem_id, $code) = $c->fetchrow_array)
        {
            push @id_problems, $problem_id;
            $pcodes{$problem_id} = $code;
        }
    }
    
    my $use_spellchecker = $is_jury && !param('nospell');

    my $need_commit = 0;
    for my $problem_id (@id_problems)
    {
        $current_pid = $problem_id;
        
        my $problem_data = $dbh->selectrow_hashref(qq~
            SELECT
                id, contest_id, title, lang, time_limit, memory_limit,
                difficulty, author, input_file, output_file,
                statement, pconstraints, input_format, output_format, explanation,
                formal_input, max_points
            FROM problems WHERE id = ?~, { Slice => {} },
            $problem_id);
        my $lang = $problem_data->{lang};

        if ($is_jury && !param('nokw'))
        {
            my $lang_col = $lang eq 'ru' ? 'name_ru' : 'name_en';
            my $kw_list = $dbh->selectcol_arrayref(qq~
                SELECT $lang_col FROM keywords K
                    INNER JOIN problem_keywords PK ON PK.keyword_id = K.id
                    WHERE PK.problem_id = ?
                    ORDER BY 1~, undef, $problem_id);
            $problem_data->{keywords} = join ', ', @$kw_list;
        }
        if ($use_spellchecker)
        {
            # Судя по документации Text::Aspell, опции нельзя менять для существующего
            # экземпляра класса, поэтому создаём каждый раз новый экземпляр.
            $spellchecker = Text::Aspell->new;
            $spellchecker->set_option('lang', $lang eq 'ru' ? 'ru_RU' : 'en_US');
        }
        else
        {
            undef $spellchecker;
        }

        if ($show_points && !$problem_data->{max_points})
        {
            $problem_data->{max_points} = CATS::RankTable::cache_max_points($problem_data->{id});
            $need_commit = 1;
        }

        $problem_data->{samples} = $dbh->selectall_arrayref(qq~
            SELECT rank, in_file, out_file
            FROM samples WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
            $problem_id);

        for my $field_name qw(statement pconstraints input_format output_format explanation)
        {
            for ($problem_data->{$field_name})
            {
                defined $_ or next;
                $text_span = '';
                $_ = $_ eq '' ? undef : Encode::encode_utf8(parse($_));
                CATS::TeX::Lite::convert_all($_);
                s/(\s|~)?-{2,3}/($1 ? '&nbsp' : '') . '&#151;'/ge; # тире
            }
        }
        $is_jury && !param('noformal') or undef $problem_data->{formal_input};
        $explain or undef $problem_data->{explanation};
        push @problems, {
            %$problem_data,
            code => $pcodes{$problem_id},
            lang_ru => $lang eq 'ru',
            lang_en => $lang eq 'en',
            show_points => $show_points,
        };
    }
    $dbh->commit if $need_commit;

    $t->param(title_suffix => $problems[0]->{title}) if @problems == 1;
    $t->param(
        problems => \@problems,
        tex_styles => CATS::TeX::Lite::styles(),
        #CATS::TeX::HTMLGen::gen_styles_html()
    );
}


sub envelope_frame
{
    init_template('main_envelope.htm');
    
    my $rid = url_param('rid') or return;

    my ($submit_time, $test_time, $state, $failed_test, $team_name, $contest_title) = $dbh->selectrow_array(qq~
        SELECT R.submit_time, R.test_time, R.state, R.failed_test, A.team_name, C.title
            FROM reqs R, contests C, accounts A
            WHERE R.id = ? AND A.id = R.account_id AND C.id = R.contest_id~, {}, $rid);
    $t->param(
        submit_time => $submit_time,
        test_time => $test_time,
        team_name => $team_name,
        contest_title => $contest_title,
        failed_test_index => $failed_test,
        state_to_display($state)
    );
}


sub preprocess_source
{
    my $h = $_[0]->{hash} = {};
    my $collapse_indents = $_[1];
    for (split /\n/, $_[0]->{src})
    {
        $_ = Encode::encode('WINDOWS-1251', $_);
        use bytes; # MD5 работает с байтами, предотвращаем upgrade до utf8
        s/\s+//g;
        if ($collapse_indents)
        {
            s/(\w+)/A/g;
        }
        else
        {
            s/(\w+)/uc($1)/eg;
        }
        s/\d+/1/g;
        $h->{Digest::MD5::md5_hex($_)} = 1;
    }
    return;
}


sub similarity_score
{
    my ($i, $j) = @_;
    my $sim = 0;
    $sim++ for grep exists $j->{$_}, keys %$i;
    $sim++ for grep exists $i->{$_}, keys %$j;
    return $sim / (keys(%$i) + keys(%$j));
}


sub similarity_frame
{
    init_template('main_similarity.htm');
    $is_jury && !$contest->is_practice or return;
    my $virtual = param('virtual') ? 1 : 0;
    $t->param(virtual => $virtual);
    my $group = param('group') ? 1 : 0;
    $t->param(group => $group);
    my $self_diff = param('self_diff') ? 1 : 0;
    $t->param(self_diff => $self_diff);
    my $collapse_idents = param('collapse_idents') ? 1 : 0;
    $t->param(collapse_idents => $collapse_idents);
    my $p = $dbh->selectall_arrayref(q~
        SELECT P.id, P.title, CP.code
            FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
            WHERE CP.contest_id = ? ORDER BY CP.code~, { Slice => {} }, $cid);
    $t->param(problems => $p);
    my ($pid) = param('pid') or return;
    $pid =~ /^\d+$/ or return;
    $_->{selected} = $_->{id} == $pid for @$p;
    # Делаем join вручную -- так быстрее
    my $acc = $dbh->selectall_hashref(q~
        SELECT CA.account_id, CA.is_jury, CA.is_virtual, A.team_name, A.city
            FROM contest_accounts CA INNER JOIN accounts A ON CA.account_id = A.id
            WHERE contest_id = ?~,
        'account_id', { Slice => {} }, $cid);
    my $reqs = $dbh->selectall_arrayref(q~
        SELECT R.id, R.account_id, S.src
            FROM reqs R INNER JOIN sources S ON S.req_id = R.id
            WHERE R.contest_id = ? AND R.problem_id = ?~, { Slice => {} }, $cid, $pid);

    preprocess_source($_, $collapse_idents) for @$reqs;

    my $threshold = 0.45;
    my @similar;
    my $by_account = {};
    for my $i (@$reqs)
    {
        my $ai = $acc->{$i->{account_id}};
        for my $j (@$reqs)
        {
            my $aj = $acc->{$j->{account_id}};
            next if
                $i->{id} >= $j->{id} ||
                (($i->{account_id} == $j->{account_id}) ^ $self_diff) ||
                $ai->{is_jury} || $aj->{is_jury} ||
                !$virtual && ($ai->{is_virtual} || $aj->{is_virtual});
            my $score = similarity_score($i->{hash}, $j->{hash});
            ($score > $threshold) ^ $self_diff or next;
            my $pair = {
                score => sprintf('%.1f%%', $score * 100), s => $score,
                n1 => [$ai], ($self_diff ? () : (n2 => [$aj])),
                href_diff => url_f('diff_runs', r1 => $i->{id}, r2 => $j->{id}),
            };
            if ($group)
            {
                for ($by_account->{$i->{account_id} . '#' . $j->{account_id}})
                {
                    $_ = $pair if !defined $_ || (($_->{s} < $pair->{s}) ^ $self_diff);
                }
            }
            else
            {
                push @similar, $pair;
            }
        }
    }
    @similar = values %$by_account if $group;
    $t->param(similar => [ sort { ($b->{s} <=> $a->{s}) * ($self_diff ? -1 : 1) } @similar ]);
}

sub about_frame
{
    init_template('main_about.htm');
    my $problem_count = $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM problems P INNER JOIN contests C ON C.id = P.contest_id
            WHERE C.is_hidden = 0 OR C.is_hidden IS NULL~);
    $t->param(problem_count => $problem_count);
}


sub authors_frame
{
    init_template('main_authors.htm');
}


sub generate_menu
{
    my $logged_on = $sid ne '';
  
    my @left_menu = (
        { item => $logged_on ? res_str(503) : res_str(500), 
          href => $logged_on ? url_function('logout', sid => $sid) : url_f('login') },
        { item => res_str(502), href => url_f('contests') },
        { item => res_str(525), href => url_f('problems') },
        { item => res_str(526), href => url_f('users') },
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

    attach_menu('left_menu', undef, [ @left_menu ]);
    attach_menu('right_menu', 'about', [ @right_menu ]) ;
    $t->param(url_authors => url_f('authors'));
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
        problems => \&problems_frame,
        problems_retest => \&problems_retest_frame,
        problem_select_testsets => \&problem_select_testsets,
        users => \&users_frame,
        user_stats => \&user_stats_frame,
        compilers => \&compilers_frame,
        judges => \&judges_frame,
        keywords => \&keywords_frame,
        import_sources => \&import_sources_frame,
        download_import_source => \&download_import_source_frame,

        answer_box => \&answer_box_frame,
        send_message_box => \&send_message_box_frame,
        
        run_log => \&run_log_frame,
        view_source => \&view_source_frame,
        download_source => \&download_source_frame,
        run_details => \&run_details_frame,
        diff_runs => \&diff_runs_frame,
        compare_tests => \&compare_tests_frame,
        
        rank_table_content => \&rank_table_content_frame,
        rank_table => \&rank_table_frame,
        rank_problem_details => \&rank_problem_details,
        problem_text => \&problem_text_frame,
        envelope => \&envelope_frame,
        about => \&about_frame,
        authors => \&authors_frame,
        static => \&static_frame,
        
        similarity => \&similarity_frame,
        personal_official_results => \&CATS::Contest::personal_official_results,
    }
}


sub accept_request                                           
{
    my $output_file = '';
    if ($is_static_page = (url_param('f') || '') eq 'static')
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
        # Функция возвращает -1 если результат генерировать не надо --
        # например, если был сделан redirect.
        ($fn->() || 0) == -1 and return;
    }
    save_settings;

    generate_menu if defined $t;
    generate_output($output_file);
}


$CATS::Misc::request_start_time = [ Time::HiRes::gettimeofday ];
CATS::DB::sql_connect;
$dbh->rollback; # на случай брошенной транзакции от предыдущего запроса

#while(CGI::Fast->new)
#{  
#    accept_request;    
#    exit if (-M $ENV{ SCRIPT_FILENAME } < 0); 
#}
#eval
    { accept_request; };

$dbh->rollback;
#sql_disconnect;

1;
