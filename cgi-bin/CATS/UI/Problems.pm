package CATS::UI::Problems;

use strict;
use warnings;

use File::stat;

use CATS::Config qw(cats_dir);
use CATS::Constants;
use CATS::DB;
use CATS::ListView qw(init_listview_template order_by sort_listview define_columns attach_listview);
use CATS::Misc qw(
    $t $is_jury $is_root $is_team $sid $cid $uid $contest $is_virtual $virtual_diff_time
    init_template msg res_str url_f auto_ext problem_status_names);
use CATS::Utils qw(url_function file_type date_to_iso);
use CATS::Data qw(:all);
use CATS::DevEnv;
use CATS::Web qw(param url_param redirect upload_source content_type headers);

use CATS::Judge;
use CATS::StaticPages;
use CATS::ProblemStorage;
use CATS::Problem::Text;
use CATS::Problem::Save;
use CATS::Problem::Source::Zip;
use CATS::Problem::Source::Git;

sub problems_change_status
{
    my $cpid = param('change_status')
        or return msg(1012);

    my $new_status = param('status');
    exists problem_status_names()->{$new_status} or return;

    $dbh->do(qq~
        UPDATE contest_problems SET status = ? WHERE contest_id = ? AND id = ?~, {},
        $new_status, $cid, $cpid);
    $dbh->commit;
    # Perhaps a 'hidden' status changed.
    CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $cpid);
}

sub problems_change_code
{
    my $cpid = param('change_code')
        or return msg(1012);
    my $new_code = param('code') || '';
    cats::is_good_problem_code($new_code) or return msg(1134);
    $dbh->do(qq~
        UPDATE contest_problems SET code = ? WHERE contest_id = ? AND id = ?~, {},
        $new_code, $cid, $cpid);
    $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $cpid);
}

sub download_problem
{
    my $pid = param('download');
    # If hash is non-empty, redirect to existing file.
    # Package size is supposed to be large enough to warrant a separate query.
    my ($hash, $status) = $dbh->selectrow_array(qq~
        SELECT P.hash, CP.status FROM problems P
        INNER JOIN contest_problems CP ON cp.problem_id = P.id
        WHERE CP.contest_id = ? AND P.id = ?~, undef,
        $cid, $pid);
    defined $status && ($is_jury || $status != $cats::problem_st_hidden)
        or return;
    undef $t;
    my $already_hashed = ensure_problem_hash($pid, \$hash);
    my $fname = "pr/problem_$hash.zip";
    my $fpath = CATS::Misc::downloads_path . $fname;
    unless($already_hashed && -f $fpath)
    {
        my ($zip) = $dbh->selectrow_array(qq~
            SELECT zip_archive FROM problems WHERE id = ?~, undef, $pid);
        CATS::BinaryFile::save($fpath, $zip);
    }
    redirect(CATS::Misc::downloads_url . $fname);
}

sub git_download_problem
{
    my $pid = param('git_download');
    my $sha = param('sha');
    $is_root && $pid or return redirect url_f('contests');
    my ($status) = $dbh->selectrow_array(qq~
        SELECT status FROM contest_problems
        WHERE contest_id = ? AND problem_id = ?~, undef,
        $cid, $pid);
    defined $status && ($is_jury || $status != $cats::problem_st_hidden)
        or return;
    undef $t;
    my ($fname, $tree_id) = CATS::ProblemStorage::get_repo_archive($pid, $sha);
    content_type('application/zip');
    headers(
        'Accept-Ranges', 'bytes',
        'Content-Length', stat($fname)->size,
        'Content-Disposition', "attachment; filename=problem_$tree_id.zip"
    );
    my $content;
    CATS::BinaryFile::load($fname, \$content) or die("open '$fname' failed: $!");
    CATS::Web::print($content);
}

sub can_upsolve
{
    my ($tag) = $dbh->selectrow_array(q~
         SELECT CA.tag FROM contest_accounts CA
             WHERE CA.contest_id = ? AND CA.account_id = ?~, undef,
         $cid, $uid || 0);
    !!(($tag || '') =~ /upsolve/);
}

sub problem_submit_too_frequent
{
    my ($submit_uid) = @_;
    # Protect from Denial of Service -- disable too frequent submissions.
    my $prev = $dbh->selectcol_arrayref(q~
        SELECT FIRST 2 CAST(CURRENT_TIMESTAMP - R.submit_time AS DOUBLE PRECISION) FROM reqs R
        WHERE R.account_id = ?
        ORDER BY R.submit_time DESC~, {},
        $submit_uid);
    my $SECONDS_PER_DAY = 24 * 60 * 60;
    ($prev->[0] || 1) < 3/$SECONDS_PER_DAY || ($prev->[1] || 1) < 60/$SECONDS_PER_DAY;
}

sub problems_submit
{
    my $pid = param('problem_id')
        or return msg(1012);
    $is_team or return msg(1116);

    # Use explicit empty string comparisons to avoid problems with solutions containing only '0'.
    my $file = param('source') // '';
    my $source_text = param('source_text') // '';
    $file ne '' || $source_text ne '' or return msg(1009);
    $file eq '' || $source_text eq '' or return msg(1042);
    length($file) <= 200 or return msg(1010);
    if ($source_text eq '') {
        $source_text = upload_source('source');
        $source_text ne '' or return msg(1011);
    }

    my $did = param('de_id') or return msg(1013);

    my ($time_since_start, $time_since_finish, $is_official, $status, $title) = $dbh->selectrow_array(qq~
        SELECT
            CAST(CURRENT_TIMESTAMP - $virtual_diff_time - C.start_date AS DOUBLE PRECISION),
            CAST(CURRENT_TIMESTAMP- $virtual_diff_time - C.finish_date AS DOUBLE PRECISION),
            C.is_official, CP.status, P.title
        FROM contests C
        INNER JOIN contest_problems CP ON CP.contest_id = C.id
        INNER JOIN problems P ON P.id = CP.problem_id
        WHERE C.id = ? AND CP.problem_id = ?~, undef,
        $cid, $pid) or return msg(1012);

    unless ($is_jury) {
        $time_since_start >= 0
            or return msg(1080);
        $time_since_finish <= 0 || $is_virtual || can_upsolve
            or return msg(1081);
        !defined $status || $status < $cats::problem_st_disabled
            or return msg(1124, $title);

        # During the official contest, do not accept submissions for other contests.
        if (!$is_official || $is_virtual) {
            my ($current_official) = $contest->current_official;
            !$current_official
                or return msg(1123, $current_official->{title});
        }
    }

    my $submit_uid = $uid // ($contest->is_practice ? get_anonymous_uid() : die);

    return msg(1131) if problem_submit_too_frequent($submit_uid);

    my $prev_reqs_count;
    if ($contest->{max_reqs} && !$is_jury) {
        $prev_reqs_count = $dbh->selectrow_array(q~
            SELECT COUNT(*) FROM reqs R
            WHERE R.account_id = ? AND R.problem_id = ? AND R.contest_id = ?~, {},
            $submit_uid, $pid, $cid);
        return msg(1137) if $prev_reqs_count >= $contest->{max_reqs};
    }

    if ($did eq 'by_extension') {
        my $de_list = CATS::DevEnv->new($dbh, active_only => 1);
        my $de = $de_list->by_file_extension($file)
            or return msg(1013);
        $did = $de->{id};
        $t->param(de_name => $de->{description});
    }

    # Forbid repeated submissions of the identical code with the same DE.
    my $source_hash = CATS::Utils::source_hash($source_text);
    my ($same_source, $prev_submit_time) = $dbh->selectrow_array(qq~
        SELECT FIRST 1 S.req_id, R.submit_time
        FROM sources S INNER JOIN reqs R ON S.req_id = R.id
        WHERE
            R.account_id = ? AND R.problem_id = ? AND
            R.contest_id = ? AND S.hash = ? AND S.de_id = ?~, {},
        $submit_uid, $pid, $cid, $source_hash, $did);
    $same_source and return msg(1132, $prev_submit_time);

    my $rid = new_id;

    my $state = $is_jury && param('ignore') ? $cats::st_ignore_submit : $cats::st_not_processed;
    $dbh->do(qq~
        INSERT INTO reqs (
            id, account_id, problem_id, contest_id,
            submit_time, test_time, result_time, state, received
        ) VALUES (
            ?,?,?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,?,?)~,
        {},
        $rid, $submit_uid, $pid, $cid, $state, 0);

    my $s = $dbh->prepare(qq~
        INSERT INTO sources(req_id, de_id, src, fname, hash) VALUES (?,?,?,?,?)~);
    $s->bind_param(1, $rid);
    $s->bind_param(2, $did);
    $s->bind_param(3, $source_text, { ora_type => 113 } ); # blob
    $s->bind_param(4, $file ? "$file" :
        "$rid." . CATS::DevEnv->new($dbh, id => $did)->default_extension($did));
    $s->bind_param(5, $source_hash);
    $s->execute;
    $dbh->commit;

    $t->param(solution_submitted => 1, href_console => url_f('console'));
    $time_since_finish > 0 ? msg(1087) :
    defined $prev_reqs_count ?
        msg(1088, $contest->{max_reqs} - $prev_reqs_count - 1) : msg(1014);
}

sub problems_submit_std_solution {
    my $pid = param('problem_id');

    defined $pid or return msg(1012);

    my ($title) = $dbh->selectrow_array(q~
        SELECT title FROM problems WHERE id = ?~, undef,
        $pid) or return msg(1012);

    my $sol_count = 0;

    my $c = $dbh->prepare(qq~
        SELECT src, de_id, fname
        FROM problem_sources
        WHERE problem_id = ? AND (stype = ? OR stype = ?)~);
    $c->execute($pid, $cats::solution, $cats::adv_solution);

    while (my ($src, $did, $fname) = $c->fetchrow_array) {
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

        ++$sol_count;
    }

    $sol_count or return msg(1106, $title);
    $dbh->commit;
    $t->param(solution_submitted => 1, href_console => url_f('console'));
    msg(1107, $title, $sol_count);
}

sub problems_mass_retest()
{
    my @retest_pids = param('problem_id') or return msg(1012);
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

sub prepare_keyword {
    my ($where, $p) = @_;
    $p->{kw} or return;
    my $name_field = 'name_' . CATS::Misc::lang();
    my ($code, $name) = $dbh->selectrow_array(qq~
        SELECT code, $name_field FROM keywords WHERE id = ?~, undef,
        $p->{kw}) or do { $p->{kw} = undef; return; };
    msg(1016, $code, $name);
    push @{$where->{cond}}, q~
        (EXISTS (SELECT 1 FROM problem_keywords PK WHERE PK.problem_id = P.id AND PK.keyword_id = ?))~;
    push @{$where->{params}}, $p->{kw};
}

sub problems_all_frame {
    my ($p) = @_;
    init_listview_template('link_problem', 'link_problem', 'problems_link.html.tt');

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

    define_columns(url_f('problems', link => $link, kw => $p->{kw}), 0, 0, [
        { caption => res_str(602), order_by => '2', width => '30%' },
        { caption => res_str(603), order_by => '3', width => '30%' },
        { caption => res_str(604), order_by => '4', width => '10%' },
        #{ caption => res_str(605), order_by => '5', width => '10%' },
    ]);

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
            # Jury can download package for any problem after linking, but not before.
            ($is_root ? (href_download => url_function('problems', sid => $sid, cid => $contest_id, download => $pid)) : ()),
            ($is_jury ? (href_problem_history => url_f('problem_history', pid => $pid)) : ()),
            linked => $linked || !$link,
            problem_id => $pid,
            problem_name => $problem_name,
            contest_name => $contest_name,
            counts => $counts,
        );
    };

    attach_listview(url_f('problems', link => $link, kw => $p->{kw}, move => $move), $fetch_record, $c);

    $t->param(
        href_action => url_f($p->{kw} ? 'keywords' : 'problems'),
        link => !$contest->is_practice && $link, move => $move, is_jury => $is_jury);

    $c->finish;
}

sub problems_udebug_frame {
    my ($p) = @_;
    init_listview_template('problems_udebug', 'problems_udebug', auto_ext('problems_udebug'));

    define_columns(url_f('problems'), 0, 0, [
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
            CP.status < $cats::problem_st_hidden AND P.lang = 'en' ~ . order_by);
    $c->execute();

    my $sol_sth = $dbh->prepare(qq~
        SELECT PS.fname, PS.src, DE.code
        FROM problem_sources PS INNER JOIN default_de DE ON DE.id = PS.de_id
        WHERE PS.problem_id = ? AND PS.stype = $cats::solution~);

    my $fetch_record = sub($)
    {
        my $r = $_[0]->fetchrow_hashref or return ();
        $sol_sth->execute($r->{pid});
        my $sols = $sol_sth->fetchall_arrayref({});
        return (
            href_view_problem => CATS::StaticPages::url_static('problem_text', cpid => $r->{cpid}),
            href_explanation => $r->{has_explanation} ?
                url_f('problem_text', cpid => $r->{cpid}, explain => 1) : '',
            href_download => url_function('problems', download => $r->{pid}),
            cpid => $r->{cpid},
            pid => $r->{pid},
            code => $r->{code},
            problem_name => $r->{problem_name},
            contest_name => $r->{contest_name},
            lang => $r->{lang},
            status_text => problem_status_names()->{$r->{status}},
            upload_date_iso => date_to_iso($r->{upload_date}),
            solutions => $sols,
        );
    };

    attach_listview(url_f('problems_udebug'), $fetch_record, $c);
    $c->finish;
}

sub problems_recalc_points()
{
    my @pids = param('problem_id') or return msg(1012);
    $dbh->do(q~
        UPDATE reqs SET points = NULL
        WHERE contest_id = ? AND problem_id IN (~ . join(',', @pids) . q~)~, undef,
        $cid);
    $dbh->commit;
    CATS::RankTable::remove_cache($cid);
}

sub problems_frame_jury_action
{
    $is_jury or return;

    defined param('link_save') and return CATS::Problem::Save::problems_link_save;
    defined param('change_status') and return problems_change_status;
    defined param('change_code') and return problems_change_code;
    defined param('replace') and return CATS::Problem::Save::problems_replace;
    defined param('add_new') and return CATS::Problem::Save::problems_add_new;
    defined param('add_remote') and return CATS::Problem::Save::problems_add_new_remote;
    defined param('std_solution') and return problems_submit_std_solution;
    defined param('mass_retest') and return problems_mass_retest;
    my $cpid = url_param('delete');
    CATS::ProblemStorage::delete($cpid) if $cpid;
}

sub problem_select_testsets_frame
{
    init_template('problem_select_testsets.html.tt');
    my $cpid = param('cpid') or return;

    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.id, P.title, CP.id AS cpid, CP.contest_id, CP.testsets, CP.points_testsets
        FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE CP.id = ?~, undef,
        $cpid) or return;
    is_jury_in_contest(contest_id => $problem->{contest_id}) or return;

    my $testsets = $dbh->selectall_arrayref(q~
        SELECT * FROM testsets WHERE problem_id = ? ORDER BY name~, { Slice => {} },
        $problem->{id});

    my $param_to_list = sub {
        my %sel;
        @sel{param($_[0])} = undef;
        join ',', map $_->{name}, grep exists $sel{$_->{id}}, @$testsets;
    };
    if (param('save')) {
        $dbh->do(q~
            UPDATE contest_problems SET testsets = ?, points_testsets = ?, max_points = NULL
            WHERE id = ?~, undef,
            map($param_to_list->("sel_$_"), qw(testsets points_testsets)), $problem->{cpid});
        $dbh->commit;
        return redirect(url_f('problems'));
    }

    my $list_to_selected = sub {
        my %sel;
        @sel{split ',', $problem->{$_[0]} || ''} = undef;
        $_->{"sel_$_[0]"} = exists $sel{$_->{name}} for @$testsets;
    };
    $list_to_selected->($_) for qw(testsets points_testsets);

    $t->param("problem_$_" => $problem->{$_}) for keys %$problem;
    $t->param(testsets => $testsets, href_select_testsets => url_f('problem_select_testsets'));
}

sub problems_retest_frame
{
    $is_jury && !$contest->is_practice or return;
    init_listview_template('problems_retest', 'problems', 'problems_retest.html.tt');

    defined param('mass_retest') and problems_mass_retest;
    defined param('recalc_points') and problems_recalc_points;

    my @cols = (
        { caption => res_str(602), order_by => '3', width => '30%' }, # name
        { caption => res_str(639), order_by => '7', width => '10%' }, # in queue
        { caption => res_str(622), order_by => '6', width => '10%' }, # status
        { caption => res_str(605), order_by => '5', width => '10%' }, # testset
        { caption => res_str(604), order_by => '8', width => '10%' }, # ok/wa/tl
    );
    define_columns(url_f('problems_retest'), 0, 0, [ @cols ]);
    my $reqs_count_sql = 'SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state =';
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
            points_testsets => $c->{points_testsets},
            in_queue => $c->{in_queue},
            href_select_testsets => url_f('problem_select_testsets', cpid => $c->{cpid}),
        );
    };
    attach_listview(url_f('problems_retest'), $fetch_record, $sth);

    $sth->finish;

    $t->param(total_queue => $total_queue);
}

sub problems_frame {
    my ($p) = @_;
    my $my_is_team =
        $is_jury || $contest->is_practice ||
        $is_team && ($contest->{time_since_finish} - $virtual_diff_time < 0 || can_upsolve);
    my $show_packages = 1;
    unless ($is_jury)
    {
        $show_packages = $contest->{show_packages};
        if ($contest->{time_since_start} < 0)
        {
            init_template(auto_ext('problems_inaccessible'));
            return msg(1130);
        }
        my $local_only = $contest->{local_only};
        if ($local_only)
        {
            my ($is_remote, $is_ooc);
            if ($uid)
            {
                ($is_remote, $is_ooc) = $dbh->selectrow_array(qq~
                    SELECT is_remote, is_ooc FROM contest_accounts WHERE contest_id = ? AND account_id = ?~,
                    {}, $cid, $uid);
            }
            if ((!defined $is_remote || $is_remote) && (!defined $is_ooc || $is_ooc))
            {
                init_template(auto_ext('problems_inaccessible'));
                $t->param(local_only => 1);
                return;
            }
        }
    }

    $is_jury && defined url_param('link') and return problems_all_frame($p);
    $p->{kw} and return problems_all_frame($p);

    init_listview_template('problems' . ($contest->is_practice ? '_practice' : ''),
        'problems', auto_ext('problems'));
    defined param('download') && $show_packages and return download_problem;
    $is_jury && defined param('git_download') && $show_packages and return git_download_problem;
    problems_frame_jury_action;

    problems_submit if defined param('submit');

    my @cols = (
        { caption => res_str(602), order_by => ($contest->is_practice ? '4' : '3'), width => '30%' },
        ($is_jury ?
        (
            { caption => res_str(622), order_by => '11', width => '10%' }, # status
            { caption => res_str(605), order_by => '15', width => '10%' }, # tests set
            { caption => res_str(635), order_by => '13', width => '5%' }, # modified by
            { caption => res_str(634), order_by => 'P.upload_date', width => '10%' }, # modification date
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
    my $hidden_problems = $is_jury ? '' : " AND CP.status < $cats::problem_st_hidden";
    # TODO: take testsets into account
    my $test_count_sql = $is_jury ? '(SELECT COUNT(*) FROM tests T WHERE T.problem_id = P.id) AS test_count,' : '';
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            ${select_code} AS code, P.title AS problem_name, OC.title AS contest_name,
            ($reqs_count_sql $cats::st_accepted$account_condition) AS accepted_count,
            ($reqs_count_sql $cats::st_wrong_answer$account_condition) AS wrong_answer_count,
            ($reqs_count_sql $cats::st_time_limit_exceeded$account_condition) AS time_limit_count,
            P.contest_id - CP.contest_id AS is_linked,
            (SELECT COUNT(*) FROM contest_problems CP1
                WHERE CP1.contest_id <> CP.contest_id AND CP1.problem_id = P.id) AS usage_count,
            OC.id AS original_contest_id, CP.status,
            P.upload_date,
            (SELECT A.login FROM accounts A WHERE A.id = P.last_modified_by) AS last_modified_by,
            SUBSTRING(P.explanation FROM 1 FOR 1) AS has_explanation,
            $test_count_sql CP.testsets, CP.points_testsets, P.lang, P.memory_limit, P.time_limit, CP.max_points, P.repo
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
        my $aid = $uid || 0; # in a case of anonymous user
        # 'ORDER BY subselect' requires re-specifying the parameter
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

    my $text_link_f = $is_jury || $contest->{is_hidden} || $contest->{local_only} ?
        \&url_f : \&CATS::StaticPages::url_static;

    my $fetch_record = sub($)
    {
        my $c = $_[0]->fetchrow_hashref or return ();
        $c->{status} ||= 0;
        my $remote_url = CATS::ProblemStorage::get_remote_url($c->{repo});
        return (
            href_delete => url_f('problems', 'delete' => $c->{cpid}),
            href_change_status => url_f('problems', 'change_status' => $c->{cpid}),
            href_change_code => url_f('problems', 'change_code' => $c->{cpid}),
            href_replace  => url_f('problems', replace => $c->{cpid}),
            href_download => url_f('problems', download => $c->{pid}),
            href_git_download => $is_jury && url_f('problems', git_download => $c->{pid}),
            href_problem_history => $is_jury && url_f('problem_history', pid => $c->{pid}),
            href_problem_details => $is_jury && url_f('problem_details', pid => $c->{pid}),
            href_original_contest =>
                url_function('problems', sid => $sid, cid => $c->{original_contest_id}, set_contest => 1),
            href_usage => url_f('contests', has_problem => $c->{pid}),
            href_problem_console => $is_jury && url_f('console', pf => $c->{pid}),
            show_packages => $show_packages,
            status => $c->{status},
            status_text => problem_status_names()->{$c->{status}},
            disabled => !$is_jury && $c->{status} == $cats::problem_st_disabled,
            href_view_problem => $text_link_f->('problem_text', cpid => $c->{cpid}),
            href_explanation => $show_packages && $c->{has_explanation} ?
                url_f('problem_text', cpid => $c->{cpid}, explain => 1) : '',
            problem_id => $c->{pid},
            cpid => $c->{cpid},
            selected => $c->{pid} == (param('problem_id') || 0),
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
            href_select_testsets => url_f('problem_select_testsets', cpid => $c->{cpid}),
            lang => $c->{lang},
            memory_limit => $c->{memory_limit} * 1024 * 1024,
            time_limit => $c->{time_limit},
            max_points => $c->{max_points},
        );
    };

    attach_listview(url_f('problems'), $fetch_record, $sth);

    $sth->finish;

    my ($jactive) = CATS::Judge::get_active_count;

    my $de_list = CATS::DevEnv->new($dbh, active_only => 1);
    my @de = (
        { de_id => 'by_extension', de_name => res_str(536) },
        map {{ de_id => $_->{id}, de_name => $_->{description} }} @{$de_list->{_de_list}} );

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
        href_action => url_f('problems'),
        contest_descr => $contest->{short_descr},
        submenu => \@submenu, title_suffix => res_str(525),
        is_team => $my_is_team, is_practice => $contest->is_practice,
        de_list => \@de, problem_codes => \@cats::problem_codes,
        contest_id => $cid, no_judges => !$jactive,
     );
}

1;
