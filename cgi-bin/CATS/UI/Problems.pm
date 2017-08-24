package CATS::UI::Problems;

use strict;
use warnings;

use List::Util qw(max);

use CATS::Config qw(cats_dir);
use CATS::Constants;
use CATS::Contest::Participate;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t $uid $user);
use CATS::DevEnv;
use CATS::Judge;
use CATS::JudgeDB;
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(auto_ext init_template url_f);
use CATS::Problem::Save;
use CATS::Problem::Source::Git;
use CATS::Problem::Source::Zip;
use CATS::Problem::Submit;
use CATS::Problem::Text;
use CATS::Problem::Utils;
use CATS::Problem::Storage;
use CATS::Redirect;
use CATS::Request;
use CATS::Settings;
use CATS::StaticPages;
use CATS::Utils qw(file_type date_to_iso redirect_url_function url_function);
use CATS::Verdicts;
use CATS::Web qw(param redirect url_param);

sub problems_change_status {
    my $cpid = param('change_status')
        or return msg(1012);

    my $new_status = param('status');
    exists CATS::Messages::problem_status_names()->{$new_status} or return;

    $dbh->do(qq~
        UPDATE contest_problems SET status = ? WHERE contest_id = ? AND id = ?~, {},
        $new_status, $cid, $cpid);
    $dbh->commit;
    # Perhaps a 'hidden' status changed.
    CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $cpid);
}

sub problems_change_code {
    my $cpid = param('change_code')
        or return msg(1012);
    my $new_code = param('code') || '';
    cats::is_good_problem_code($new_code) or return msg(1134);
    $dbh->do(q~
        UPDATE contest_problems SET code = ? WHERE contest_id = ? AND id = ?~, undef,
        $new_code, $cid, $cpid);
    $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $cpid);
}

sub problems_mass_retest {
    my @retest_pids = param('problem_id') or return msg(1012);
    my $all_runs = param('all_runs');
    my %ignore_states;
    for (param('ignore_states')) {
        my $st = $CATS::Verdicts::name_to_state->{$_ // ''};
        $ignore_states{$st} = 1 if defined $st;
    }
    my $count = 0;
    for my $retest_pid (@retest_pids) {
        my $runs = $dbh->selectall_arrayref(q~
            SELECT id, account_id, state FROM reqs
            WHERE contest_id = ? AND problem_id = ? ORDER BY id DESC~,
            { Slice => {} },
            $cid, $retest_pid
        );
        my %accounts;
        for (@$runs) {
            next if !$all_runs && $accounts{$_->{account_id}}++;
            next if $ignore_states{$_->{state} // 0};
            my $fields = {
                state => $cats::st_not_processed, judge_id => undef, points => undef, testsets => undef };
            CATS::Request::enforce_state($_->{id}, $fields) and ++$count;
        }
        $dbh->commit;
    }
    return msg(1128, $count);
}

sub prepare_keyword {
    my ($where, $p) = @_;
    $p->{kw} or return;
    my $name_field = 'name_' . CATS::Settings::lang();
    my ($code, $name) = $dbh->selectrow_array(qq~
        SELECT code, $name_field FROM keywords WHERE id = ?~, undef,
        $p->{kw}) or do { $p->{kw} = undef; return; };
    msg(1016, $code, $name);
    push @{$where->{cond}}, q~
        (EXISTS (SELECT 1 FROM problem_keywords PK WHERE PK.problem_id = P.id AND PK.keyword_id = ?))~;
    push @{$where->{params}}, $p->{kw};
}

sub define_common_searches {
    my ($lv) = @_;

    $lv->define_db_searches([ map "P.$_", qw(
        id title contest_id author upload_date lang run_method last_modified_by max_points
        statement explanation pconstraints input_format output_format formal_input json_data
        statement_url explanation_url
    ), @cats::limits_fields ]);

    $lv->define_db_searches({
        map {
            join('_', split /\W+/, $cats::source_module_names{$_}) =>
            "(SELECT COUNT (*) FROM problem_sources PS WHERE PS.problem_id = P.id AND PS.stype = $_)"
        } keys %cats::source_modules
    });

    $lv->define_enums({ run_method => CATS::Problem::Utils::run_method_enum() });
}

sub problems_all_frame {
    my ($p) = @_;
    my $lv = CATS::ListView->new(name => 'link_problem', template => 'problems_link.html.tt');

    my $link = url_param('link');
    my $move = url_param('move') || 0;

    if ($link) {
        my @u = $contest->unused_problem_codes
            or return msg(1017);
        $t->param(unused_codes => [ @u ]);
    }

    my $where =
        $is_root ? {
            cond => [], params => [] }
        : !$link ? {
            cond => ['CURRENT_TIMESTAMP > C.finish_date AND (C.is_hidden = 0 OR C.is_hidden IS NULL)'],
            params => [] }
        : {
            cond => [q~
            (
                EXISTS (
                    SELECT 1 FROM contest_accounts
                    WHERE contest_id = C.id AND account_id = ? AND is_jury = 1
                    ) OR CURRENT_TIMESTAMP > C.finish_date AND (C.is_hidden = 0 OR C.is_hidden IS NULL)
            )~],
            params => [ $uid // 0 ]
        };
    prepare_keyword($where, $p);
    my $where_cond = join(' AND ', @{$where->{cond}}) || '1=1';

    $lv->define_columns(url_f('problems', link => $link, kw => $p->{kw}), 0, 0, [
        { caption => res_str(602), order_by => '2', width => '30%' },
        { caption => res_str(603), order_by => '3', width => '30%' },
        { caption => res_str(604), order_by => '4', width => '10%' },
        #{ caption => res_str(605), order_by => '5', width => '10%' },
    ]);
    define_common_searches($lv);
    $lv->define_db_searches({ contest_title => 'C.title'});

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
        WHERE $where_cond ~ . $lv->maybe_where_cond . $lv->order_by);
    $c->execute($cid, @{$where->{params}}, $lv->where_params);

    my $fetch_record = sub {
        my ($pid, $problem_name, $contest_name, $contest_id, $counts, $linked) = $_[0]->fetchrow_array
            or return ();
        my %pp = (sid => $sid, cid => $contest_id, pid => $pid);
        return (
            href_view_problem => url_f('problem_text', pid => $pid),
            href_view_contest => url_function('problems', sid => $sid, cid => $contest_id),
            # Jury can download package for any problem after linking, but not before.
            ($is_root ? (href_download => url_function('problem_download', %pp)) : ()),
            ($is_jury ? (href_problem_history => url_function('problem_history', %pp)) : ()),
            linked => $linked || !$link,
            problem_id => $pid,
            problem_name => $problem_name,
            contest_name => $contest_name,
            counts => $counts,
        );
    };

    $lv->attach(url_f('problems', link => $link, kw => $p->{kw}, move => $move), $fetch_record, $c);
    $c->finish;

    $t->param(
        href_action => url_f('problems'),
        link => !$contest->is_practice && $link, move => $move);
}

sub problems_udebug_frame {
    my ($p) = @_;
    my $lv = CATS::ListView->new(name => 'problems_udebug', template => auto_ext('problems_udebug'));

    $lv->define_columns(url_f('problems'), 0, 0, [
        { caption => res_str(602), order_by => '2', width => '30%' },
    ]);

    my $c = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid, CP.code, P.title AS problem_name, P.lang, C.title AS contest_name,
            SUBSTRING(P.explanation FROM 1 FOR 1) AS has_explanation,
            CP.status, P.upload_date
        FROM contest_problems CP
            INNER JOIN problems P ON CP.problem_id = P.id
            INNER JOIN contests C ON CP.contest_id = C.id
        WHERE
            C.is_official = 1 AND C.show_packages = 1 AND
            CURRENT_TIMESTAMP > C.finish_date AND (C.is_hidden = 0 OR C.is_hidden IS NULL) AND
            CP.status < $cats::problem_st_hidden AND P.lang = 'en' ~ . $lv->order_by);
    $c->execute();

    my $sol_sth = $dbh->prepare(qq~
        SELECT PS.fname, PS.src, DE.code
        FROM problem_sources PS INNER JOIN default_de DE ON DE.id = PS.de_id
        WHERE PS.problem_id = ? AND PS.stype = $cats::solution~);

    my $fetch_record = sub {
        my $r = $_[0]->fetchrow_hashref or return ();
        $sol_sth->execute($r->{pid});
        my $sols = $sol_sth->fetchall_arrayref({});
        return (
            href_view_problem => CATS::StaticPages::url_static('problem_text', cpid => $r->{cpid}),
            href_explanation => $r->{has_explanation} ?
                url_f('problem_text', cpid => $r->{cpid}, explain => 1) : '',
            href_download => url_function('problem_download', pid => $r->{pid}),
            cpid => $r->{cpid},
            pid => $r->{pid},
            code => $r->{code},
            problem_name => $r->{problem_name},
            contest_name => $r->{contest_name},
            lang => $r->{lang},
            status_text => CATS::Messages::problem_status_names()->{$r->{status}},
            upload_date_iso => date_to_iso($r->{upload_date}),
            solutions => $sols,
        );
    };

    $lv->attach(url_f('problems_udebug'), $fetch_record, $c);
    $c->finish;
}

sub problems_recalc_points {
    my @pids = param('problem_id') or return msg(1012);
    my $pids = join ',', grep /^\d+$/, @pids or return msg(1012);
    $dbh->do(qq~
        UPDATE reqs SET points = NULL
        WHERE contest_id = ? AND problem_id IN ($pids)~, undef,
        $cid);
    $dbh->commit;
    CATS::RankTable::remove_cache($cid);
}

sub problems_frame_jury_action {
    my ($p) = @_;
    $is_jury or return;

    defined param('link_save') and return CATS::Problem::Save::problems_link_save;
    defined param('change_status') and return problems_change_status;
    defined param('change_code') and return problems_change_code;
    $p->{replace} and return CATS::Problem::Save::problems_replace;
    $p->{add_new} and return CATS::Problem::Save::problems_add_new;
    $p->{add_remote} and return CATS::Problem::Save::problems_add_new_remote;
    $p->{std_solution} and return CATS::Problem::Submit::problems_submit_std_solution($p);
    CATS::Problem::Storage::delete($p->{delete_problem}) if $p->{delete_problem};
}

sub problem_status_names_enum {
    my ($lv) = @_;
    my $psn = CATS::Messages::problem_status_names();
    my $inverse_psn = {};
    $inverse_psn->{$psn->{$_}} = $_ for keys %$psn;
    $lv->define_enums({ status => $inverse_psn });
    $psn;
}

my $retest_default_ignore = { IS => 1, SV => 1 };

sub problems_retest_frame {
    $is_jury && !$contest->is_practice or return;
    my $lv = CATS::ListView->new(
        name => 'problems_retest', array_name => 'problems', template => 'problems_retest.html.tt');

    defined param('mass_retest') and problems_mass_retest;
    defined param('recalc_points') and problems_recalc_points;

    my @cols = (
        { caption => res_str(602), order_by => '3', width => '30%' }, # name
        { caption => res_str(639), order_by => '7', width => '10%' }, # in queue
        { caption => res_str(622), order_by => '6', width => '10%' }, # status
        { caption => res_str(605), order_by => '5', width => '10%' }, # testset
        { caption => res_str(604), order_by => '8', width => '10%' }, # ok/wa/tl
    );
    $lv->define_columns(url_f('problems_retest'), 0, 0, [ @cols ]);
    define_common_searches($lv);
    $lv->define_db_searches([ qw(
        CP.code CP.testsets CP.points_testsets CP.status
    ) ]);

    my $psn = problem_status_names_enum($lv);

    my $reqs_count_sql = q~
        SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.contest_id = CP.contest_id AND D.state =~;
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            CP.code, P.title AS problem_name, CP.testsets, CP.points_testsets, CP.status,
            ($reqs_count_sql $cats::st_accepted) AS accepted_count,
            ($reqs_count_sql $cats::st_wrong_answer) AS wrong_answer_count,
            ($reqs_count_sql $cats::st_time_limit_exceeded) AS time_limit_count,
            (SELECT COUNT(*) FROM reqs R
                WHERE R.contest_id = CP.contest_id AND R.problem_id = CP.problem_id AND
                R.state < $cats::request_processed) AS in_queue
        FROM problems P INNER JOIN contest_problems CP ON CP.problem_id = P.id
        WHERE CP.contest_id = ?~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $total_queue = 0;
    my $fetch_record = sub {
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
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
            points_testsets => $c->{points_testsets},
            in_queue => $c->{in_queue},
            href_select_testsets => url_f('problem_select_testsets', pid => $c->{pid}, from_problems => 1),
        );
    };
    $lv->attach(url_f('problems_retest'), $fetch_record, $sth);

    $sth->finish;

    $t->param(
        total_queue => $total_queue,
        verdicts => [ map +{ short => $_->[0], checked => $retest_default_ignore->{$_->[0]} },
            @$CATS::Verdicts::name_to_state_sorted ],
    );
}

sub problems_frame {
    my ($p) = @_;

    my $show_packages = 1;
    unless ($is_jury) {
        $show_packages = $contest->{show_packages};
        if (!$contest->has_started($user->{diff_time})) {
            init_template(auto_ext('problems_inaccessible'));
            return msg(1130);
        }
        my $local_only = $contest->{local_only};
        if ($local_only) {
            my ($is_remote, $is_ooc);
            if ($uid) {
                ($is_remote, $is_ooc) = $dbh->selectrow_array(q~
                    SELECT is_remote, is_ooc FROM contest_accounts
                    WHERE contest_id = ? AND account_id = ?~, undef,
                    $cid, $uid);
            }
            if ((!defined $is_remote || $is_remote) && (!defined $is_ooc || $is_ooc)) {
                init_template(auto_ext('problems_inaccessible'));
                $t->param(local_only => 1);
                return;
            }
        }
    }

    $is_jury && defined url_param('link') and return problems_all_frame($p);
    $p->{kw} and return problems_all_frame($p);

    my $lv = CATS::ListView->new(
        name => 'problems' . ($contest->is_practice ? '_practice' : ''),
        array_name => 'problems',
        template => auto_ext('problems'));
    problems_frame_jury_action($p);

    CATS::Problem::Submit::problems_submit($p) if $p->{submit};
    CATS::Contest::Participate::online if $p->{participate_online};
    CATS::Contest::Participate::virtual if $p->{participate_virtual};

    my @cols = (
        { caption => res_str(602), order_by => ($contest->is_practice ? 'P.title' : 3), width => '25%' },
        ($is_jury ?
        (
            { caption => res_str(622), order_by => 'CP.status', width => '8%' },
            { caption => res_str(605), order_by => 'CP.testsets', width => '12%' },
            { caption => res_str(629), order_by => 'CP.tags', width => '8%' },
            { caption => res_str(635), order_by => 'last_modified_by', width => '5%', col => 'Mu' },
            { caption => res_str(634), order_by => 'P.upload_date', width => '10%', col => 'Mt' },
        )
        : ()
        ),
        ($contest->is_practice ?
        { caption => res_str(603), order_by => '5', width => '15%' } : () # contest
        ),
        { caption => res_str(604), order_by => '6', width => '12%', col => 'Vc' }, # ok/wa/tl
    );
    $lv->define_columns(url_f('problems'), 0, 0, \@cols);
    define_common_searches($lv);
    $lv->define_db_searches([ qw(
        CP.code CP.testsets CP.tags CP.points_testsets CP.status
    ) ]);
    my $psn = problem_status_names_enum($lv);

    my $reqs_count_sql = 'SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state =';
    my $account_condition = $contest->is_practice ? '' : ' AND D.account_id = ?';
    my $select_code = $contest->is_practice ? 'NULL' : 'CP.code';
    my $hidden_problems = $is_jury ? '' : " AND CP.status < $cats::problem_st_hidden";
    # TODO: take testsets into account
    my $test_count_sql = $is_jury ? '(SELECT COUNT(*) FROM tests T WHERE T.problem_id = P.id) AS test_count,' : '';
    my $limits_str = join ', ', map "P.$_", @cats::limits_fields;
    my $counts = $lv->visible_cols->{Vc} ? qq~
        ($reqs_count_sql $cats::st_accepted$account_condition) AS accepted_count,
        ($reqs_count_sql $cats::st_wrong_answer$account_condition) AS wrong_answer_count,
        ($reqs_count_sql $cats::st_time_limit_exceeded$account_condition) AS time_limit_count,
        (SELECT R.id || ' ' || R.state FROM reqs R
            WHERE R.problem_id = P.id AND R.account_id = ? AND R.contest_id = CP.contest_id
            ORDER BY R.submit_time DESC ROWS 1) AS last_submission~
    : q~
        NULL AS accepted_count,
        NULL AS wrong_answer_count,
        NULL AS time_limit_count,
        NULL AS last_submission~;
    # Concatenate last submission fields to work around absence of tuples.
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            $select_code AS code, P.title AS problem_name, OC.title AS contest_name,
            $counts,
            P.contest_id - CP.contest_id AS is_linked,
            (SELECT COUNT(*) FROM contest_problems CP1
                WHERE CP1.contest_id <> CP.contest_id AND CP1.problem_id = P.id) AS usage_count,
            OC.id AS original_contest_id, CP.status,
            P.upload_date,
            (SELECT A.login FROM accounts A WHERE A.id = P.last_modified_by) AS last_modified_by,
            SUBSTRING(P.explanation FROM 1 FOR 1) AS has_explanation,
            $test_count_sql CP.testsets, CP.points_testsets, P.lang, $limits_str,
            CP.max_points, P.repo, CP.tags, P.statement_url, P.explanation_url
        FROM problems P
        INNER JOIN contest_problems CP ON CP.problem_id = P.id
        INNER JOIN contests OC ON OC.id = P.contest_id
        WHERE CP.contest_id = ?$hidden_problems
        ~ . $lv->maybe_where_cond . $lv->order_by
    );
    my $aid = $uid || 0; # in a case of anonymous user
    my @params =
        !$lv->visible_cols->{Vc} ? () :
        $contest->is_practice ? ($aid) :
        ($aid) x 4;
    $sth->execute(@params, $cid, $lv->where_params);

    my @status_list;
    if ($is_jury) {
        my $n = CATS::Messages::problem_status_names();
        for (sort keys %$n) {
            push @status_list, { id => $_, name => $n->{$_} };
        }
        $t->param(status_list => \@status_list, editable => 1);
    }

    my $text_link_f = $is_jury || $contest->{is_hidden} || $contest->{local_only} ?
        \&url_f : \&CATS::StaticPages::url_static;

    my $fetch_record = sub {
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
        my $remote_url = CATS::Problem::Storage::get_remote_url($c->{repo});

        my %hrefs_view;
        for (qw(statement explanation)) {
            if (my $h = $c->{"${_}_url"}) {
                $hrefs_view{$_} = $h =~ s|^file://|| ?
                    CATS::Problem::Text::save_attachment($h, 0, $c->{pid}) :
                    redirect_url_function($h, pid => $c->{pid}, sid => $sid, cid => $cid);
            }
        }
        $c->{has_explanation} ||= $hrefs_view{explanation};

        my ($last_request, $last_verdict) = split ' ', $c->{last_submission} || '';

        return (
            href_delete => url_f('problems', delete_problem => $c->{cpid}),
            href_change_status => url_f('problems', change_status => $c->{cpid}),
            href_change_code => url_f('problems', change_code => $c->{cpid}),
            href_replace  => url_f('problems', replace => $c->{cpid}),
            href_download => url_f('problem_download', pid => $c->{pid}),
            href_problem_details => $is_jury && url_f('problem_details', pid => $c->{pid}),
            href_original_contest =>
                url_function('problems', sid => $sid, cid => $c->{original_contest_id}, set_contest => 1),
            href_usage => url_f('contests', search => "has_problem($c->{pid})", filter => 'all'),
            href_problem_console => $uid &&
                url_f('console', search => "problem_id=$c->{pid}", uf => ($is_jury ? undef : $uid),
                    se => 'problem', i_value => -1, show_results => 1),
            href_select_testsets => url_f('problem_select_testsets', pid => $c->{pid}, from_problems => 1),
            href_select_tags => url_f('problem_select_tags', pid => $c->{pid}, from_problems => 1),
            href_last_request => ($last_request ? url_f('run_details', rid => $last_request) : ''),

            show_packages => $show_packages,
            status => $c->{status},
            status_text => $psn->{$c->{status}},
            disabled => !$is_jury && $c->{status} == $cats::problem_st_disabled,
            href_view_problem => $hrefs_view{statement} || $text_link_f->('problem_text', cpid => $c->{cpid}),
            href_explanation => $show_packages && $c->{has_explanation} ?
                $hrefs_view{explanation} || url_f('problem_text', cpid => $c->{cpid}, explain => 1) : '',
            problem_id => $c->{pid},
            cpid => $c->{cpid},
            selected => $c->{pid} == ($p->{problem_id} || 0),
            code => $c->{code},
            problem_name => $c->{problem_name},
            is_linked => $c->{is_linked},
            remote_url => $remote_url,
            usage_count => $c->{usage_count},
            contest_name => $c->{contest_name},
            accept_count => $c->{accepted_count},
            wa_count => $c->{wrong_answer_count},
            tle_count => $c->{time_limit_count},
            upload_date => $c->{upload_date},
            upload_date_iso => date_to_iso($c->{upload_date}),
            last_modified_by => $c->{last_modified_by},
            testsets => $c->{testsets} || '*',
            points_testsets => $c->{points_testsets},
            test_count => $c->{test_count},
            lang => $c->{lang},
            memory_limit => $c->{memory_limit} * 1024 * 1024,
            time_limit => $c->{time_limit},
            write_limit => $c->{write_limit},
            max_points => $c->{max_points},
            tags => $c->{tags},
            last_verdict => $CATS::Verdicts::state_to_name->{$last_verdict || ''},
        );
    };

    $lv->attach(url_f('problems'), $fetch_record, $sth);

    $sth->finish;

    my ($jactive) = CATS::Judge::get_active_count;

    my $de_list = CATS::DevEnv->new(CATS::JudgeDB::get_DEs({ active_only => 1 }));
    my @de = (
        { de_id => 'by_extension', de_name => res_str(536) },
        map {{ de_id => $_->{id}, de_name => $_->{description} }} @{$de_list->des} );

    my $pt_url = sub {{ href => $_[0], item => ($_[1] || res_str(538)), target => '_blank' }};
    my $pr = $contest->is_practice;
    my @submenu = grep $_,
        ($is_jury ? (
            !$pr && $pt_url->(url_f('problem_text', nospell => 1, nokw => 1, notime => 1, noformal => 1)),
            !$pr && $pt_url->(url_f('problem_text'), res_str(555)),
            { href => url_f('problems', link => 1), item => res_str(540) },
            { href => url_f('problems', link => 1, move => 1), item => res_str(551) },
            !$pr && ({ href => url_f('problems_retest'), item => res_str(556) }),
            { href => url_f('contests_prizes', clist => $cid), item => res_str(565) },
        )
        : (
            !$pr && $pt_url->($text_link_f->('problem_text', cid => $cid)),
        )),
        { href => url_f('contests', params => $cid), item => res_str(546) };

    $t->param(
        href_login => url_f('login', redir => CATS::Redirect::pack_params),
        CATS::Contest::Participate::flags_can_participate,
        contest_descr => $contest->{short_descr},
        submenu => \@submenu, title_suffix => res_str(525),
        is_user => $uid,
        can_submit => $is_jury ||
            $user->{is_participant} &&
            ($user->{is_virtual} || !$contest->has_finished($user->{diff_time} + $user->{ext_time})),
        is_practice => $contest->is_practice,
        de_list => \@de, problem_codes => \@cats::problem_codes,
        contest_id => $cid, no_judges => !$jactive,
     );
}

sub problem_text_frame { goto \&CATS::Problem::Text::problem_text }

1;
