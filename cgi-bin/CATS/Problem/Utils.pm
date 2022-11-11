package CATS::Problem::Utils;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB qw(:DEFAULT $db);
use CATS::Globals qw($cid $contest $is_jury $t $user);
use CATS::Messages qw(res_str msg);
use CATS::Output qw(url_f);
use CATS::Settings;

# If the problem was not downloaded yet, generate a hash for it.
sub ensure_problem_hash {
    my ($problem_id, $hash, $need_commit) = @_;
    return 1 if $$hash;
    my @ch = ('a'..'z', 'A'..'Z', '0'..'9');
    $$hash = join '', map @ch[rand @ch], 1..32;
    $dbh->do(q~
        UPDATE problems SET hash = ? WHERE id = ?~, undef,
        $$hash, $problem_id);
    $dbh->commit if $need_commit;
    return 0;
}

sub gen_group_text {
    my ($t) = @_;
    $t->{gen_group} ? "$t->{gen_name} GROUP" :
    $t->{gen_name} ? "$t->{gen_name} $t->{param}" : '';
}

sub run_method_enum() {+{
    default => $cats::rm_default,
    interactive => $cats::rm_interactive,
    competitive => $cats::rm_competitive,
    competitive_modules => $cats::rm_competitive_modules,
}}

my $problem_submenu = [
    { href => 'problem_details', item => 504 },
    { href => 'problem_history', item => 568 },
    { href => 'compare_tests', item => 552 },
    { href => 'problem_select_testsets', item => 505 },
    { href => 'problem_test_data', item => 508 },
    { href => 'problem_limits', item => 507 },
    { href => 'problem_select_tags', item => 506 },
    { href => 'problem_des', item => 517 },
    { href => 'problem_link', item => 540 },
    { href => 'problem_snippets', item => 698 },
];

sub problem_submenu {
    my ($selected_href, $pid) = @_;
    $t->param(
        submenu => [ map +{
            href => url_f($_->{href}, pid => $pid),
            item => res_str($_->{item}),
            selected => $_->{href} eq $selected_href }, @$problem_submenu
        ]
    );
}

sub problems_change_status {
    my ($p) = @_;
    my $cpid = $p->{change_status} or return msg(1012);

    my $new_status = $p->{status};
    exists CATS::Messages::problem_status_names()->{$p->{status}} or return;

    $dbh->do(qq~
        UPDATE contest_problems SET status = ? WHERE contest_id = ? AND id = ?~, {},
        $p->{status}, $cid, $cpid);
    $dbh->commit;
    # Perhaps a 'hidden' status changed.
    CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $cpid);
}

sub problems_change_code {
    my ($p) = @_;
    my $cpid = $p->{change_code} or return msg(1012);
    defined $p->{code} || defined $p->{move} or return msg(1134);

    if ($p->{code}) {
        $dbh->do(q~
            UPDATE contest_problems SET code = ? WHERE contest_id = ? AND id = ?~, undef,
            $p->{code}, $cid, $cpid);
        $dbh->commit;
        CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $cpid);
    }
    elsif ($p->{move}) {
        my ($old_code) = $dbh->selectrow_array(q~
            SELECT code FROM contest_problems WHERE contest_id = ? AND id = ?~, undef,
            $cid, $cpid);
        my ($cmp, $dir) = $p->{move} eq 'up' ? ('<', 'DESC') : ('>', 'ASC');
        my ($neighbor_id, $neighbor_code) = $dbh->selectrow_array(qq~
            SELECT id, code FROM contest_problems
            WHERE contest_id = ? AND code $cmp ? ORDER BY code $dir $db->{LIMIT} 1~, undef,
            $cid, $old_code) or return;
        defined $old_code && defined $neighbor_code && $old_code ne $neighbor_code or return;
        $dbh->do(q~
            UPDATE contest_problems SET code = ? WHERE contest_id = ? AND id = ?~, undef,
            $old_code, $cid, $neighbor_id);
        $dbh->do(q~
            UPDATE contest_problems SET code = ? WHERE contest_id = ? AND id = ?~, undef,
            $neighbor_code, $cid, $cpid);
        $dbh->commit;
        CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => [ $cpid, $neighbor_id ]);
    }
}

sub problem_status_names_enum {
    my ($lv) = @_;
    my $psn = CATS::Messages::problem_status_names();
    my $inverse_psn = {};
    $inverse_psn->{$psn->{$_}} = $_ for keys %$psn;
    $lv->define_enums({ status => $inverse_psn });
    $psn;
}

sub define_common_searches {
    my ($lv) = @_;

    $lv->define_db_searches([ map "P.$_", qw(
        id title contest_id author upload_date lang run_method last_modified_by max_points
        input_file output_file
        statement explanation pconstraints input_format output_format formal_input json_data
        statement_url explanation_url
    ), @cats::limits_fields ]);

    $lv->define_db_searches([ qw(
        CP.code CP.testsets CP.tags CP.points_testsets CP.status CP.deadline
    ) ]);
    $lv->default_searches([ qw(code title) ]);

    my @sources =
        map [ join('_', split(/\W+/, $cats::source_module_names{$_})), $_ ], keys %cats::source_modules;
    $lv->define_db_searches({
        test_count => q~
            (SELECT COUNT(*) FROM tests T WHERE T.problem_id = P.id)~,
        attachment_count => q~
            (SELECT COUNT(*) FROM problem_attachments PA WHERE PA.problem_id = P.id)~,
        contest_count => q~
            (SELECT COUNT(*) FROM contest_problems CP2 WHERE CP2.problem_id = P.id)~,
        (map { $_->[0] . '_count' => qq~
            (SELECT COUNT (*) FROM problem_sources PS
                INNER JOIN problem_sources_local PSL on PS.id = PSL.id
                WHERE PS.problem_id = P.id AND PSL.stype = $_->[1])~
        } @sources),
        (map { $_->[0] => qq~
            (SELECT PSL.src FROM problem_sources PS
                INNER JOIN problem_sources_local PSL on PS.id = PSL.id
                WHERE PS.problem_id = P.id AND PSL.stype = $_->[1]
                ROWS 1)~
        } @sources),
        problem_snippets => q~
            (SELECT COUNT(*) FROM problem_snippets PSN WHERE PSN.problem_id = CP.problem_id)~,
        snippets => q~
            (SELECT COUNT(*) FROM snippets SN
                WHERE SN.problem_id = CP.problem_id AND SN.contest_id = CP.contest_id)~,
        until_deadline => q~CAST(CP.deadline - CURRENT_TIMESTAMP AS DOUBLE PRECISION)~,
    });
    $lv->define_casts({ map { $_ => 'VARCHAR(100)' } 'code', map $_->[0], @sources });

    $lv->define_enums({
        run_method => CATS::Problem::Utils::run_method_enum(),
        contest_id => { this => $cid },
    });
}

sub define_kw_subquery {
    my ($lv) = @_;

    # Keywords are only in English and Russian for now.
    my $lang = CATS::Settings::lang;
    my $name_field = 'name_' . ($lang =~ /^(en|ru)$/ ? $lang : 'en');

    $lv->define_subqueries({
        has_kw => {
            sq => q~(EXISTS (
                SELECT 1 FROM problem_keywords PK
                WHERE PK.problem_id = P.id AND PK.keyword_id = ?))~,
            m => 1016,
            t => qq~SELECT code, $name_field FROM keywords WHERE id = ?~,
        },
        has_kw_code => {
            sq => q~(EXISTS (
                SELECT 1 FROM problem_keywords PK
                INNER JOIN keywords K ON K.id = PK.keyword_id
                WHERE PK.problem_id = P.id AND K.code = ?))~,
            m => 1016,
            t => qq~SELECT code, $name_field FROM keywords WHERE code = ?~,
        },
        has_kw_code_prefix => {
            sq => q~(EXISTS (
                SELECT 1 FROM problem_keywords PK
                INNER JOIN keywords K ON K.id = PK.keyword_id
                WHERE PK.problem_id = P.id AND K.code LIKE ? || '%'))~,
            m => 1050,
            t => undef,
        },
        has_import_guid => {
            sq => q~(EXISTS (
                SELECT 1 FROM problem_sources PS
                INNER JOIN problem_sources_imported PSI ON PS.id = PSI.id
                WHERE PS.problem_id = P.id AND PSI.guid LIKE ? || '%'))~,
            m => 1204,
            t => q~SELECT guid, fname FROM problem_sources_local WHERE guid = ?~,
        },
        is_used_by_contest => {
            sq => q~(EXISTS (
                SELECT 1 FROM contest_problems CP
                WHERE CP.problem_id = P.id AND CP.contest_id = ?))~,
            m => 1048,
            t => q~SELECT title FROM contests WHERE id = ?~,
        },
        from_contest_with_tag => {
            sq => q~(EXISTS (
                SELECT 1 FROM contest_tags CT
                INNER JOIN contest_contest_tags CCT
                    ON CCT.contest_id = P.contest_id AND CCT.tag_id = CT.id
                WHERE CT.name = ?))~,
            m => 1048,
            t => q~SELECT name FROM contest_tags CT WHERE name = ?~,
        },
        last_used_before => {
            sq => q~(CAST(? AS DATE) > ALL (
                SELECT C2.start_date FROM contests C2
                INNER JOIN contest_problems CP2
                    ON CP2.contest_id = C2.id
                WHERE CP2.problem_id = P.id))~,
            m => 1224,
            t => undef,
        },
        has_de_code_local => {
            sq => q~(EXISTS (
                SELECT 1 FROM problem_sources PS
                INNER JOIN problem_sources_local PSL ON PS.id = PSL.id
                INNER JOIN default_de DE ON PSL.de_id = DE.id
                WHERE PS.problem_id = P.id AND DE.code = ?))~,
            m => 1225,
            t => q~SELECT DE.description FROM default_de DE WHERE DE.code = ?~,
        },
        has_attachment_like => {
            sq => q~(EXISTS (
                SELECT 1 FROM problem_attachments PA
                WHERE PA.problem_id = P.id AND PA.file_name LIKE ?))~,
            m => 1244,
            t => undef,
        },
    });
}

sub can_download_package {
    $is_jury ||
        $contest->{show_packages} &&
        $contest->{time_since_start} > 0 &&
        (!$contest->{local_only} || $user->{is_local}) &&
        (!$contest->{is_hidden} || $user->{is_participant});
}

sub round_time_limit { $_[0] = int($_[0] * 100) / 100 if $_[0] }

sub clear_test_data {
    my ($problem_id) = @_;
    $dbh->do(q~
        UPDATE tests T SET in_file = NULL, in_file_size = NULL
        WHERE T.in_file_size IS NOT NULL AND T.problem_id = ?~, undef,
        $problem_id);
    $dbh->do(q~
        UPDATE tests T SET out_file = NULL, out_file_size = NULL
        WHERE T.out_file_size IS NOT NULL AND T.problem_id = ?~, undef,
        $problem_id);
}

1;
