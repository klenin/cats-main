package CATS::Router;

use strict;
use warnings;

use File::Spec;

use CATS::ApiJudge;
use CATS::Web qw(url_param param);

BEGIN {
    require $_ for glob File::Spec->catfile($ENV{CATS_DIR} || '.', 'CATS', 'UI', '*.pm');
}

my $bool = qr/1/;
my $int = qr/\d+/;
my $int_list = qr/[\d,]+/;
my $fixed = qr/[+-]?([0-9]*[.])?[0-9]+/;
my $sha = qr/[a-h0-9]+/;
my $str = qr/.+/;
my $ident = qr/[a-zA-Z_]+/;

sub main_routes() {
    {
        login => [ \&CATS::UI::LoginLogout::login_frame,
            logout => $bool, login => $str, passwd => $str, redir => $str, ],
        logout => \&CATS::UI::LoginLogout::logout_frame,
        registration => [ \&CATS::UI::Users::registration_frame, register => $bool, ],
        profile => [ \&CATS::UI::Users::profile_frame, json => $bool, clear => $bool, edit_save => $str, ],
        contests => [ \&CATS::UI::Contests::contests_frame,
            summary_rank => $bool, create_group => $bool,
            online_registration => $bool, virtual_registration => $bool,
            edit_save => $bool, new_save => $bool, id => $int,
        ],
        contest_sites => [ \&CATS::UI::Sites::contest_sites_frame, ],
        contest_sites_edit => [ \&CATS::UI::Sites::contest_sites_edit_frame,
            site_id => $int,
            diff_time => $fixed, diff_units => $ident,
            ext_time => $fixed, ext_units => $ident,
            save => $bool, ],

        console_content => \&CATS::UI::Console::content_frame,
        console => [ \&CATS::UI::Console::console_frame,
            delete_question => $int, delete_message => $int, send_question => $bool, question_text => $str,
        ],
        console_export => \&CATS::UI::Console::export_frame,
        console_graphs => \&CATS::UI::Console::graphs_frame,

        problems => [
            \&CATS::UI::Problems::problems_frame,
            kw => $int, problem_id => $int,
            participate_online => $bool, participate_virtual => $bool,
            submit => $bool, replace => $bool, add_new => $bool,
            add_remote => $bool, std_solution => $bool, delete_problem => $int,
            de_id => qr/\d+|by_extension/, ignore => $bool,
            change_status => $int, status => $int,
            change_code => $int, code => qr/[A-Z1-9]/,
            link_save => $bool, move => $bool,
        ],
        problems_udebug => [ \&CATS::UI::Problems::problems_udebug_frame, ],
        problems_retest => \&CATS::UI::Problems::problems_retest_frame,
        problem_select_testsets => [
            \&CATS::UI::ProblemDetails::problem_select_testsets_frame,
            pid => $int, save => $bool, from_problems => $bool, ],
        problem_select_tags => [
            \&CATS::UI::ProblemDetails::problem_select_tags_frame,
            pid => $int, tags => $str, save => $bool, from_problems => $bool, ],
        problem_limits => [ \&CATS::UI::ProblemDetails::problem_limits_frame,
            pid => $int, cpid => $int, override => $bool, clear_override => $bool, ],
        problem_download => [ \&CATS::UI::ProblemDetails::problem_download, pid => $int, ],
        problem_git_package => [ \&CATS::UI::ProblemDetails::problem_git_package, pid => $int, sha => $sha, ],
        problem_details => [ \&CATS::UI::ProblemDetails::problem_details_frame, pid => $int, ],
        problem_test_data => [
            \&CATS::UI::ProblemDetails::problem_test_data_frame,
            pid => $int, test_rank => $int, clear_test_data => $bool ],
        problem_link => [ \&CATS::UI::ProblemDetails::problem_link_frame,
            pid => $int,
        ],
        problem_history => [ \&CATS::UI::ProblemHistory::problem_history_frame,
            a => $ident, pid => $int, pull => $bool, replace => $bool,
            is_amend => $bool, allow_rename => $bool, ],

        users => [
            \&CATS::UI::Users::users_frame,
            save_attributes => $bool,
            set_tag => $bool, tag_to_set => $str,
            set_site => $bool, site_id => $int,
            send_message => $bool, message_text => $str, send_all => $bool, send_all_contests => $bool,
        ],
        users_all_settings => [ \&CATS::UI::Users::users_all_settings_frame, ],
        users_import => [ \&CATS::UI::Users::users_import_frame,
            go => $bool, do_import => $bool, user_list => $str, ],
        users_add_participants => [ \&CATS::UI::Users::users_add_participants_frame,
            logins_to_add => $str, make_jury => $bool, by_login => $bool,
            source_cid => $int, from_contest => $bool, include_ooc => $bool,
        ],
        user_stats => \&CATS::UI::Users::user_stats_frame,
        user_settings => [ \&CATS::UI::Users::user_settings_frame, uid => $int, clear => $bool, ],
        user_ip => [ \&CATS::UI::Users::user_ip_frame, uid => $int, ],
        user_vdiff => [ \&CATS::UI::Users::user_vdiff_frame,
            uid => $int,
            diff_time => $fixed, diff_units => $ident,
            ext_time => $fixed, ext_units => $ident,
            is_virtual => $ident, save => $bool, ],
        impersonate => [ \&CATS::UI::Users::impersonate_frame, uid => $int, ],

        compilers => \&CATS::UI::Compilers::compilers_frame,
        judges => \&CATS::UI::Judges::judges_frame,
        keywords => \&CATS::UI::Keywords::keywords_frame,
        import_sources => \&CATS::UI::ImportSources::import_sources_frame,
        download_import_source => [ \&CATS::UI::ImportSources::download_frame, psid => $int, ],
        prizes => \&CATS::UI::Prizes::prizes_frame,
        contests_prizes => \&CATS::UI::Prizes::contests_prizes_frame,
        sites => \&CATS::UI::Sites::sites_frame,

        answer_box => [ \&CATS::UI::Messages::answer_box_frame,
            qid => $int, clarify => 1, answer_text => $str, ],
        send_message_box => [ \&CATS::UI::Messages::send_message_box_frame,
            caid => $int, send => $bool, message_text => $str, ],

        run_log => [ \&CATS::UI::RunDetails::run_log_frame, rid => $int, delete_log => $bool, ],
        view_source => [ \&CATS::UI::RunDetails::view_source_frame,
            rid => $int, replace => $bool, de_id => $int, syntax => $ident, ],
        download_source => \&CATS::UI::RunDetails::download_source_frame,
        run_details => \&CATS::UI::RunDetails::run_details_frame,
        visualize_test => [ \&CATS::UI::RunDetails::visualize_test_frame,
            rid => $int, vid => $int, test_rank => $int, ],
        diff_runs => [ \&CATS::UI::RunDetails::diff_runs_frame, r1 => $int, r2 => $int, ],
        view_test_details => [
            \&CATS::UI::RunDetails::view_test_details_frame,
            rid => $int, test_rank => $int, delete_request_outputs => $bool, delete_test_output => $bool, ],
        request_params => [
            \&CATS::UI::RunDetails::request_params_frame,
            rid => $int,
            status_ok => $bool,
            reinstall => $bool,
            retest => $bool,
            clone => $bool,
            delete_request => $bool,
            set_state => $bool,
            failed_test => $int,
            points => $int,
            state => $ident,
            set_tag => $bool, tag => $str,
        ],

        test_diff => [ \&CATS::UI::Stats::test_diff_frame, pid => $int, test => $int, ],
        compare_tests => \&CATS::UI::Stats::compare_tests_frame,
        rank_table_content => \&CATS::UI::RankTable::rank_table_content_frame,
        rank_table => \&CATS::UI::RankTable::rank_table_frame,
        rank_problem_details => \&CATS::UI::RankTable::rank_problem_details,
        problem_text => [ \&CATS::UI::Problems::problem_text_frame,
            pid => $int, cpid => $int, cid => $int,
            explain => $bool, nospell => $bool, noformal => $bool, pl => $ident, nokw => $bool,
            tags => $str, raw => $bool, nomath => $bool,
        ],
        envelope => [ \&CATS::UI::Messages::envelope_frame, rid => $int, ],
        about => \&CATS::UI::About::about_frame,

        similarity => [ \&CATS::UI::Stats::similarity_frame,
            virtual => $bool, jury => $bool, group => $bool, self_diff => $bool, threshold => $int,
            collapse_idents => $bool, all_contests=> $bool, pid => $int, account_id => $int,
        ],
        personal_official_results => \&CATS::UI::ContestResults::personal_official_results,
    }
}

sub api_judge_routes() {
    {
        get_judge_id => \&CATS::ApiJudge::get_judge_id,
        api_judge_get_des => [ \&CATS::ApiJudge::get_DEs, active_only => $bool, id => $int, ],
        api_judge_get_problem => [ \&CATS::ApiJudge::get_problem, pid => $int, ],
        api_judge_get_problem_sources => [ \&CATS::ApiJudge::get_problem_sources, pid => $int, ],
        api_judge_get_problem_tests => [ \&CATS::ApiJudge::get_problem_tests, pid => $int, ],
        api_judge_is_problem_uptodate => [ \&CATS::ApiJudge::is_problem_uptodate, pid => $int, date => $str, ],
        api_judge_save_log_dump => [ \&CATS::ApiJudge::save_log_dump, req_id => $int, dump => undef, ],
        api_judge_select_request => [
            \&CATS::ApiJudge::select_request,
            de_version => $int,
            map { +"de_bits$_" => $int } 1..$cats::de_req_bitfields_count,
        ],
        api_judge_set_request_state => [
            \&CATS::ApiJudge::set_request_state,
            req_id => $int,
            state => $int,
            problem_id => $int,
            contest_id => $int,
            failed_test => $int,
        ],
        api_judge_delete_req_details => [ \&CATS::ApiJudge::delete_req_details, req_id => $int, ],
        api_judge_insert_req_details => [ \&CATS::ApiJudge::insert_req_details, params => $str, ],
        api_judge_save_input_test_data => [
            \&CATS::ApiJudge::save_input_test_data,
            problem_id => $int,
            test_rank => $int,
            input => undef,
            input_size => $int,
        ],
        api_judge_save_answer_test_data => [
            \&CATS::ApiJudge::save_answer_test_data,
            problem_id => $int,
            test_rank => $int,
            answer => undef,
            answer_size => $int,
        ],
        api_judge_get_testset => [ \&CATS::ApiJudge::get_testset, req_id => $int, update => $int, ],
    }
}

sub parse_uri {
    CATS::Web::get_uri =~ m~/cats/(|main.pl)$~;
}

sub route {
    my $function = url_param('f') || '';
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
            $p->{$name} = $value if defined $value && (!defined($type) || $value =~ /^$type$/);
        }
    }

    ($fn, $p);
}

1;
