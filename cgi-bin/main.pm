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
use CATS::UI::Contests;
use CATS::UI::Users;
use CATS::UI::ImportSources;

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
        registration => \&CATS::UI::Users::registration_frame,
        settings => \&CATS::UI::Users::settings_frame,
        contests => \&CATS::UI::Contests::contests_frame,
        console_content => \&CATS::Console::content_frame,
        console => \&CATS::Console::console_frame,
        console_export => \&CATS::Console::export,
        console_graphs => \&CATS::Console::graphs,
        problems => \&CATS::UI::Problems::problems_frame,
        problems_retest => \&CATS::UI::Problems::problems_retest_frame,
        problem_select_testsets => \&CATS::UI::Problems::problem_select_testsets_frame,
        problem_history => \&CATS::UI::Problems::problem_history_frame,
        users => \&CATS::UI::Users::users_frame,
        users_import => \&CATS::UI::Users::users_import_frame,
        user_stats => \&CATS::UI::Users::user_stats_frame,
        compilers => \&CATS::UI::Compilers::compilers_frame,
        judges => \&CATS::UI::Judges::judges_frame,
        keywords => \&CATS::UI::Keywords::keywords_frame,
        import_sources => \&CATS::UI::ImportSources::import_sources_frame,
        download_import_source => \&CATS::UI::ImportSources::download_frame,
        prizes => \&prizes_frame,

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
