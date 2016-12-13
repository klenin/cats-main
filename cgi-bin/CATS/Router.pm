package CATS::Router;

use strict;
use warnings;

use CATS::Web qw(url_param param);

use CATS::ApiJudge;
use CATS::Console;
use CATS::Contest::Results;
use CATS::Problem::Text;
use CATS::RunDetails;

use CATS::UI::About;
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

my $function;

my $int = qr/\d+/;
sub main_routes() {
    {
        login => \&CATS::UI::LoginLogout::login_frame,
        logout => \&CATS::UI::LoginLogout::logout_frame,
        registration => \&CATS::UI::Users::registration_frame,
        settings => \&CATS::UI::Users::settings_frame,
        contests => [ \&CATS::UI::Contests::contests_frame, has_problem => $int, ],
        console_content => \&CATS::Console::content_frame,
        console => \&CATS::Console::console_frame,
        console_export => \&CATS::Console::export,
        console_graphs => \&CATS::Console::graphs,
        problems => [ \&CATS::UI::Problems::problems_frame, kw => $int, ],
        problems_udebug => [ \&CATS::UI::Problems::problems_udebug_frame, ],
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
        contests_prizes => \&CATS::UI::Prizes::contests_prizes_frame,

        answer_box => \&CATS::UI::Messages::answer_box_frame,
        send_message_box => \&CATS::UI::Messages::send_message_box_frame,

        run_log => \&CATS::RunDetails::run_log_frame,
        view_source => \&CATS::RunDetails::view_source_frame,
        download_source => \&CATS::RunDetails::download_source_frame,
        run_details => \&CATS::RunDetails::run_details_frame,
        visualize_test => \&CATS::RunDetails::visualize_test_frame,
        diff_runs => [ \&CATS::RunDetails::diff_runs_frame, r1 => $int, r2 => $int, ],

        test_diff => \&CATS::UI::Stats::test_diff_frame,
        compare_tests => \&CATS::UI::Stats::compare_tests_frame,
        rank_table_content => \&CATS::UI::RankTable::rank_table_content_frame,
        rank_table => \&CATS::UI::RankTable::rank_table_frame,
        rank_problem_details => \&CATS::UI::RankTable::rank_problem_details,
        problem_text => \&CATS::Problem::Text::problem_text_frame,
        envelope => \&CATS::UI::Messages::envelope_frame,
        about => \&CATS::UI::About::about_frame,

        similarity => \&CATS::UI::Stats::similarity_frame,
        personal_official_results => \&CATS::Contest::personal_official_results,
    }
}

sub api_judge_routes() {
    {
        get_judge_id => \&CATS::ApiJudge::get_judge_id,
        api_judge_update_state => \&CATS::ApiJudge::update_state,
    }
}

sub parse_uri {
    CATS::Web::get_uri =~ m~/cats/(|main.pl)$~;
}

sub route {
    $function = url_param('f') || '';
    my $route =
        main_routes->{$function} ||
        api_judge_routes->{$function} ||
        \&CATS::UI::About::about_frame;
    my $fn = $route;
    my $p = {};
    if (ref $route eq 'ARRAY') {
        $fn = shift @$route;
        while (@$route) {
            my $name = shift @$route;
            my $type = shift @$route;
            my $value = param($name);
            $p->{$name} = $value if defined $value && $value =~ /^$type$/;
        }
    }

    ($fn, $p);
}

1;
