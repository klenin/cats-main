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


use CATS::Web qw(param url_param redirect init_request get_return_code);
use CATS::DB;
use CATS::Constants;
use CATS::BinaryFile;
use CATS::DevEnv;
use CATS::Misc qw(:all);
use CATS::Utils qw(coalesce url_function state_to_display param_on);
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
use CATS::UI::LoginLogout;
use CATS::UI::RankTable;

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
        login => \&CATS::UI::LoginLogout::login_frame,
        logout => \&CATS::UI::LoginLogout::logout_frame,
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
        prizes => \&CATS::UI::Prizes::prizes_frame,

        answer_box => \&CATS::UI::Messages::answer_box_frame,
        send_message_box => \&CATS::UI::Messages::send_message_box_frame,

        run_log => \&CATS::RunDetails::run_log_frame,
        view_source => \&CATS::RunDetails::view_source_frame,
        download_source => \&CATS::RunDetails::download_source_frame,
        run_details => \&CATS::RunDetails::run_details_frame,
        diff_runs => \&CATS::RunDetails::diff_runs_frame,

        test_diff => \&CATS::UI::Stats::test_diff_frame,
        compare_tests => \&CATS::UI::Stats::compare_tests_frame,
        rank_table_content => \&CATS::UI::RankTable::rank_table_content_frame,
        rank_table => \&CATS::UI::RankTable::rank_table_frame,
        rank_problem_details => \&CATS::UI::RankTable::rank_problem_details,
        problem_text => \&CATS::Problem::Text::problem_text_frame,
        envelope => \&CATS::UI::Messages::envelope_frame,
        about => \&about_frame,

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

use LWP::UserAgent;

sub handler {
    my $r = shift;
    init_request($r);
    if ((param('f') || '') eq 'proxy') {
        my $url = param('u') or die;
        $url =~ m|^http://neerc.ifmo.ru/| or die;
        my $ua = LWP::UserAgent->new;
        $ua->proxy(http => 'http://proxy.dvfu.ru:3128');
        my $res = $ua->request(HTTP::Request->new(GET => $url));
        $res->is_success or die $res->status_line;
        CATS::Web::content_type('text/plain');
        print $res->content;
        return get_return_code();
    }
    $CATS::Misc::request_start_time = [ Time::HiRes::gettimeofday ];
    CATS::DB::sql_connect;
    $dbh->rollback; # In a case of abandoned transaction

    accept_request();
    $dbh->rollback;

    return get_return_code();
}

1;
