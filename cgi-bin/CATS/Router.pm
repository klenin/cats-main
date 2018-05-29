package CATS::Router;

use strict;
use warnings;

use FindBin;
use File::Spec;

use CATS::ApiJudge;
use CATS::Utils;
use CATS::Web qw(url_param param);

BEGIN {
    require $_ for glob File::Spec->catfile($ENV{CATS_DIR} || $FindBin::Bin, 'CATS', 'UI', '*.pm');
}

sub bool() { qr/^1$/ }
sub bool0() { qr/^[01]$/ }
sub integer() { qr/^[0-9]+$/ } # 'int' is reserved.
sub fixed() { qr/^[+-]?([0-9]*[.])?[0-9]+$/ }
sub sha() { qr/^[a-h0-9]+$/ }
sub str() { qr/./ }
sub ident() { qr/^[a-zA-Z][a-zA-Z_0-9]*$/ }
sub problem_code { qr/^[A-Za-z0-9]{1,3}$/ }

sub check_encoding { $_[0] && CATS::Utils::encodings->{$_[0]} }
sub encoding() { \&check_encoding }
sub encoding_default($) {
    my ($default) = @_;
    sub { check_encoding($_[0]) ? $_[0] : ($_[0] = $default) };
}

my ($main_routes, $api_judge_routes);

BEGIN {
    for my $name (qw(array_of clist_of required)) {
        no strict 'refs';
        # Prototype to allow acting as a unary operator.
        *$name = sub($) {
            ref $_[0] eq 'HASH' or return { $name => 1, type => $_[0] };
            $_[0]->{$name} = 1;
            $_[0];
        };
    }
}

# Separate BEGIN block to allow prototypes to have effect.
BEGIN {

my %console_params = (
    selection => clist_of integer,
    show_contests => bool0, show_messages => bool0, show_results => bool0,
);

my %form_params = (new => bool, edit => integer, delete => integer, edit_save => bool);

$main_routes = {
    login => [ \&CATS::UI::LoginLogout::login_frame,
        logout => bool, login => str, passwd => str, redir => str, cid => integer, ],
    logout => \&CATS::UI::LoginLogout::logout_frame,
    registration => [ \&CATS::UI::UserDetails::registration_frame, register => bool, ],
    profile => [ \&CATS::UI::UserDetails::profile_frame,
        json => bool, clear => bool, edit_save => str, set_password => bool, ],
    contests => [ \&CATS::UI::Contests::contests_frame,
        summary_rank => bool, create_group => bool, delete => integer,
        online_registration => bool, virtual_registration => bool,
        edit_save => bool, new_save => bool, id => integer, original_id => integer,
        contests_selection => array_of integer,
        (map { $_ => bool } CATS::UI::Contests::contest_checkbox_params),
        (map { $_ => str } CATS::UI::Contests::contest_string_params),
        exclude_verdict => array_of ident,
        ical => bool, set_contest => bool, filter => ident,
    ],
    contests_new => [ \&CATS::UI::Contests::contests_new_frame, ],
    contest_params => [ \&CATS::UI::Contests::contest_params_frame, id => integer, ],
    contest_sites => [ \&CATS::UI::Sites::contest_sites_frame, add => bool, delete => integer, check => array_of integer, ],
    contest_sites_edit => [ \&CATS::UI::Sites::contest_sites_edit_frame,
        site_id => integer,
        diff_time => fixed, diff_units => ident,
        ext_time => fixed, ext_units => ident,
        save => bool, ],

    console_content => [ \&CATS::UI::Console::console_content_frame,
        %console_params,
    ],
    console => [ \&CATS::UI::Console::console_frame,
        delete_question => integer, delete_message => integer, send_question => bool, question_text => str,
        %console_params,
    ],
    console_export => \&CATS::UI::Console::export_frame,
    console_graphs => \&CATS::UI::Console::graphs_frame,

    problems => [
        \&CATS::UI::Problems::problems_frame,
        problem_id => integer,
        problems_selection => array_of integer,
        participate_online => bool, participate_virtual => bool,
        submit => bool, replace => bool, add_new => bool,
        add_remote => bool, std_solution => bool, delete_problem => integer,
        de_id => qr/\d+|by_extension/, ignore => bool,
        change_status => integer, status => integer,
        change_code => integer, code => problem_code,
        link_save => bool, move => bool,
    ],
    problems_all => [
        \&CATS::UI::Problems::problems_all_frame,
        kw => integer, link => bool, move => bool,
    ],
    problems_udebug => [ \&CATS::UI::Problems::problems_udebug_frame, ],
    problems_retest => [ \&CATS::UI::ProblemsRetest::problems_retest_frame,
        mass_retest => bool, recalc_points => bool, all_runs => bool,
        problem_id => array_of integer, ignore_states => array_of ident,
    ],
    problem_select_testsets => [
        \&CATS::UI::ProblemDetails::problem_select_testsets_frame,
        pid => integer, save => bool, from_problems => bool,
        sel_testsets => array_of integer,
        sel_points_testsets => array_of integer,
    ],
    problem_select_tags => [
        \&CATS::UI::ProblemDetails::problem_select_tags_frame,
        pid => integer, tags => str, save => bool, from_problems => bool, ],
    problem_des => [
        \&CATS::UI::ProblemDetails::problem_des_frame,
        pid => integer, allow => array_of integer, save => bool, ],
    problem_limits => [ \&CATS::UI::ProblemDetails::problem_limits_frame,
        pid => integer, cpid => integer, override => bool, clear_override => bool,
        (map { $_ => str } @cats::limits_fields),
    ],
    problem_download => [ \&CATS::UI::ProblemDetails::problem_download, pid => integer, ],
    problem_git_package => [ \&CATS::UI::ProblemDetails::problem_git_package, pid => integer, sha => sha, ],
    problem_details => [ \&CATS::UI::ProblemDetails::problem_details_frame, pid => integer, ],
    problem_test_data => [
        \&CATS::UI::ProblemDetails::problem_test_data_frame,
        pid => integer, test_rank => integer, clear_test_data => bool, clear_input_hashes => bool, ],
    problem_link => [ \&CATS::UI::ProblemDetails::problem_link_frame,
        pid => integer, contest_id => integer,
        link_to => bool, move_to => bool, move_from => bool,
        code => problem_code,
    ],

    problem_history => [ \&CATS::UI::ProblemHistory::problem_history_frame,
        a => ident, pid => integer, pull => bool, replace => bool,
        is_amend => bool, allow_rename => bool, ],
    problem_history_edit => [ \&CATS::UI::ProblemHistory::problem_history_edit_frame,
        pid => required integer, hb => required sha, file => required str,
        save => bool, src_enc => encoding, message => str, source => undef,
        is_amend => bool,
    ],
    problem_history_blob => [ \&CATS::UI::ProblemHistory::problem_history_blob_frame,
        pid => required integer, hb => required sha, file => required str, src_enc => str,
    ],
    problem_history_raw => [ \&CATS::UI::ProblemHistory::problem_history_raw_frame,
        pid => required integer, hb => required sha, file => required str,
    ],
    problem_history_commit => [ \&CATS::UI::ProblemHistory::problem_history_commit_frame,
        pid => required integer, h => required sha, src_enc => str,
    ],
    problem_history_tree => [ \&CATS::UI::ProblemHistory::problem_history_tree_frame,
        pid => required integer, hb => required sha, file => str, repo_enc => encoding,
    ],

    users => [
        \&CATS::UI::Users::users_frame,
        save_attributes => bool,
        set_tag => bool, tag_to_set => str,
        set_site => bool, site_id => integer,
        gen_passwords => bool, password_len => integer,
        send_message => bool, message_text => str, send_all => bool, send_all_contests => bool,
        delete_user => integer, new_save => bool, edit_save => bool,
        user_set => clist_of integer, sel => array_of integer,
    ],
    users_all_settings => [ \&CATS::UI::Users::users_all_settings_frame, ],
    users_import => [ \&CATS::UI::Users::users_import_frame,
        go => bool, do_import => bool, user_list => str, ],
    users_add_participants => [ \&CATS::UI::Users::users_add_participants_frame,
        logins_to_add => str, make_jury => bool, by_login => bool,
        source_cid => integer, from_contest => bool, include_ooc => bool,
    ],
    users_new => \&CATS::UI::UserDetails::users_new_frame,
    users_edit => [ \&CATS::UI::UserDetails::users_edit_frame, uid => integer, ],
    user_stats => [ \&CATS::UI::UserDetails::user_stats_frame, uid => integer, ],
    user_settings => [ \&CATS::UI::UserDetails::user_settings_frame, uid => integer, clear => bool, ],
    user_ip => [ \&CATS::UI::UserDetails::user_ip_frame, uid => integer, ],
    user_vdiff => [ \&CATS::UI::UserDetails::user_vdiff_frame,
        uid => integer,
        diff_time => fixed, diff_units => ident,
        ext_time => fixed, ext_units => ident,
        is_virtual => bool, save => bool, finish_now => bool ],
    user_contacts => [ \&CATS::UI::UserDetails::user_contacts_frame,
        uid => integer, %form_params, handle => str,
    ],
    impersonate => [ \&CATS::UI::UserDetails::impersonate_frame, uid => integer, ],
    contact_types => [
        \&CATS::UI::ContactTypes::contact_types_frame,
        %form_params,
        map { $_ => str } CATS::UI::ContactTypes::fields,
    ],
    compilers => [ \&CATS::UI::Compilers::compilers_frame,
        %form_params,
        locked => bool,
        map { $_ => str } CATS::UI::Compilers::fields,
    ],
    judges => [ \&CATS::UI::Judges::judges_frame,
        ping => integer, %form_params,
        id => integer, judge_name => str, account_name => str, pin_mode => integer,
    ],
    keywords => [ \&CATS::UI::Keywords::keywords_frame,
        %form_params,
        map { $_ => str } CATS::UI::Keywords::fields,
    ],
    import_sources => [ \&CATS::UI::ImportSources::import_sources_frame, ],
    download_import_source => [ \&CATS::UI::ImportSources::download_frame, psid => integer, ],
    prizes => \&CATS::UI::Prizes::prizes_frame,
    contests_prizes => \&CATS::UI::Prizes::contests_prizes_frame,
    sites => [ \&CATS::UI::Sites::sites_frame,
        %form_params, name => str, org_name => str,
    ],
    snippets => [ \&CATS::UI::Snippets::snippet_frame,
        %form_params, map { $_ => str } CATS::UI::Snippets::fields,
    ],
    answer_box => [ \&CATS::UI::Messages::answer_box_frame,
        qid => integer, clarify => 1, answer_text => str, ],
    send_message_box => [ \&CATS::UI::Messages::send_message_box_frame,
        caid => integer, send => bool, message_text => str, ],

    run_log => [ \&CATS::UI::RunDetails::run_log_frame, rid => integer, delete_log => bool, ],
    view_source => [ \&CATS::UI::RunDetails::view_source_frame,
        rid => integer, replace => bool, de_id => integer, syntax => ident,
        src_enc => encoding_default('WINDOWS-1251'),
    ],
    download_source => [ \&CATS::UI::RunDetails::download_source_frame,
        rid => integer,
        src_enc => encoding_default('WINDOWS-1251'),
    ],
    run_details => [ \&CATS::UI::RunDetails::run_details_frame,
        rid => required clist_of integer,
        comment_enc => encoding_default('UTF-8'),
    ],
    job_details => [ \&CATS::UI::Jobs::job_details_frame,
        jid => integer, delete_log => bool,
    ],
    visualize_test => [ \&CATS::UI::RunDetails::visualize_test_frame,
        rid => integer, vid => integer, test_rank => integer, ],
    diff_runs => [ \&CATS::UI::RunDetails::diff_runs_frame,
        r1 => integer, r2 => integer,
        src_enc => encoding_default('WINDOWS-1251'),
    ],
    view_test_details => [
        \&CATS::UI::RunDetails::view_test_details_frame,
        rid => integer, test_rank => integer, delete_request_outputs => bool, delete_test_output => bool, ],
    request_params => [
        \&CATS::UI::RunDetails::request_params_frame,
        rid => integer,
        status_ok => bool,
        reinstall => bool,
        retest => bool,
        clone => bool,
        delete_request => bool,
        set_state => bool,
        failed_test => integer,
        points => integer,
        state => ident,
        set_tag => bool, tag => str,
        (map { $_ => str, "set_$_" => bool } @cats::limits_fields),
        testsets => str,
        judge => str, set_judge => bool,
    ],

    test_diff => [ \&CATS::UI::Stats::test_diff_frame, pid => integer, test => integer, ],
    compare_tests => [ \&CATS::UI::Stats::compare_tests_frame, pid => required integer, ],
    rank_table_content => [ \&CATS::UI::RankTable::rank_table_content_frame,
        (map { $_ => bool } @CATS::UI::RankTable::router_bool_params),
        clist => clist_of integer,
    ],
    rank_table => [ \&CATS::UI::RankTable::rank_table_frame,
        (map { $_ => bool } @CATS::UI::RankTable::router_bool_params),
        filter => str,
        clist => clist_of integer,
        sites => clist_of integer,
    ],
    rank_problem_details => \&CATS::UI::RankTable::rank_problem_details,
    problem_text => [ \&CATS::UI::Problems::problem_text_frame,
        pid => integer, cpid => integer, cid => integer,
        explain => bool, nospell => bool, noformal => bool, pl => ident, nokw => bool,
        tags => str, raw => bool, nomath => bool, uid => integer,
    ],
    get_snippets => [ \&CATS::UI::Snippets::get_snippets,
        cpid => integer, snippet_names => array_of ident, uid => integer,
    ],
    envelope => [ \&CATS::UI::Messages::envelope_frame, rid => integer, ],
    about => \&CATS::UI::About::about_frame,

    similarity => [ \&CATS::UI::Stats::similarity_frame,
        virtual => bool, jury => bool, group => bool, self_diff => bool, threshold => integer,
        collapse_idents => bool, all_contests=> bool, pid => integer, account_id => integer, cont => bool,
    ],
    personal_official_results => [ \&CATS::UI::ContestResults::personal_official_results,
        search => str, group => ident,
    ],
    wiki => [ \&CATS::UI::Wiki::wiki_frame, name => str, ],
    wiki_pages => [ \&CATS::UI::Wiki::wiki_pages_frame, %form_params, name => str, ],
    wiki_edit => [ \&CATS::UI::Wiki::wiki_edit_frame,
        delete => integer, edit_cancel => bool, edit_save => bool, name => str,
        wiki_lang => ident, wiki_id => integer, id => integer, title => str, text=> str,
    ],
    jobs => [ \&CATS::UI::Jobs::jobs_frame, delete => integer, ],
};

$api_judge_routes = {
    get_judge_id => \&CATS::ApiJudge::get_judge_id,
    api_judge_get_des => [ \&CATS::ApiJudge::get_DEs, active_only => bool, id => integer, ],
    api_judge_get_problem => [ \&CATS::ApiJudge::get_problem, pid => integer, ],
    api_judge_get_problem_sources => [ \&CATS::ApiJudge::get_problem_sources, pid => integer, ],
    api_judge_get_problem_tests => [ \&CATS::ApiJudge::get_problem_tests, pid => integer, ],
    api_judge_get_snippet_text => [ \&CATS::ApiJudge::get_snippet_text, pid => integer, cid => integer,
        uid => integer, name => ident, ],
    api_judge_get_problem_tags => [ \&CATS::ApiJudge::get_problem_tags, pid => integer, cid => integer, ],
    api_judge_get_problem_snippets => [ \&CATS::ApiJudge::get_problem_snippets, pid => integer, ],
    api_judge_is_problem_uptodate => [ \&CATS::ApiJudge::is_problem_uptodate, pid => integer, date => str, ],
    api_judge_save_logs => [ \&CATS::ApiJudge::save_logs, job_id => integer, dump => undef, ],
    api_judge_select_request => [
        \&CATS::ApiJudge::select_request,
        de_version => integer,
        map { +"de_bits$_" => integer } 1..$cats::de_req_bitfields_count,
    ],
    api_judge_set_request_state => [
        \&CATS::ApiJudge::set_request_state,
        req_id => integer,
        state => integer,
        problem_id => integer,
        contest_id => integer,
        failed_test => integer,
    ],
    api_judge_finish_job => [
        \&CATS::ApiJudge::finish_job,
        job_id => integer,
    ],
    api_judge_delete_req_details => [ \&CATS::ApiJudge::delete_req_details, req_id => integer, ],
    api_judge_insert_req_details => [ \&CATS::ApiJudge::insert_req_details, params => str, ],
    api_judge_save_input_test_data => [
        \&CATS::ApiJudge::save_input_test_data,
        problem_id => integer,
        test_rank => integer,
        input => undef,
        input_size => integer,
    ],
    api_judge_save_answer_test_data => [
        \&CATS::ApiJudge::save_answer_test_data,
        problem_id => integer,
        test_rank => integer,
        answer => undef,
        answer_size => integer,
    ],
    api_judge_save_problem_snippet => [
        \&CATS::ApiJudge::save_problem_snippet,
        problem_id => integer,
        contest_id => integer,
        account_id => integer,
        snippet_name => ident,
        text => undef,
    ],
    api_judge_get_testset => [ \&CATS::ApiJudge::get_testset, req_id => integer, update => integer, ],
};

}

sub parse_uri { $_[0]->get_uri =~ m~/cats/(|main.pl)$~ }

sub check_type { !defined $_[1] || $_[0] =~ $_[1] }

sub common_params {
    my ($p) = @_;
    my $json = param('json');
    $p->{json} = 1 if $json;
    $p->{jsonp} = $json if $json && $json =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/;
    $p->{enc} = param('enc') if check_encoding(param('enc'));
    $p->{f} = url_param('f') || '';
}

sub route {
    my ($p) = @_;
    my $default_route = \&CATS::UI::About::about_frame;

    my $route =
        $main_routes->{$p->{f}} ||
        $api_judge_routes->{$p->{f}}
        or return $default_route;
    ref $route eq 'ARRAY' or return $route;
    my $fn = $route->[0];

    for (my $i = 1; $i < @$route; $i += 2) {
        my $name = $route->[$i];
        my $type = $route->[$i + 1];

        if (ref $type eq 'CODE') {
            my $value = param($name);
            $p->{$name} = $value if $type->($value);
            next;
        }
        if (ref $type ne 'HASH') {
            my $value = param($name);
            $p->{$name} = $value if defined $value && check_type($value, $type);
            next;
        }

        if ($type->{array_of}) {
            my @values = grep check_type($_, $type->{type}), param($name);
            return $default_route if !@values && $type->{required};
            $p->{$name} = \@values;
            next;
        }

        my $value = param($name);
        if ($type->{clist_of}) {
            my @values = grep check_type($_, $type->{type}), split ',', $value // '';
            return $default_route if !@values && $type->{required};
            $p->{$name} = \@values;
            next;
        }

        if (!defined $value) {
            return $default_route if $type->{required};
            next;
        }

        if (check_type($value, $type->{type})) {
            $p->{$name} = $value;
        }
        elsif ($type->{required}) {
            return $default_route;
        }
    }

    $fn;
}

1;
