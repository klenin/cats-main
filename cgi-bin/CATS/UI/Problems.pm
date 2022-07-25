package CATS::UI::Problems;

use strict;
use warnings;

use JSON::XS;
use List::Util qw(max);

use CATS::Config qw(cats_dir);
use CATS::Constants;
use CATS::Contest::Participate;
use CATS::DB;
use CATS::DevEnv;
use CATS::Examus;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t $uid $user);
use CATS::Judge;
use CATS::JudgeDB;
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f url_f_cid);
use CATS::Problem::Save;
use CATS::Problem::Source::Git;
use CATS::Problem::Source::Zip;
use CATS::Problem::Submit;
use CATS::Problem::Tags;
use CATS::Problem::Text;
use CATS::Problem::Utils;
use CATS::Problem::Storage;
use CATS::Redirect;
use CATS::Request;
use CATS::Settings;
use CATS::StaticPages;
use CATS::Utils qw(file_type redirect_url_function);
use CATS::Verdicts;

sub _href_problem_console {
    my ($pid) = @_;
    $uid && url_f('console',
        search => "problem_id=$pid", uf => ($is_jury ? undef : $uid),
        se => 'problem', i_value => -1, show_results => 1)
}

sub problems_all_frame {
    my ($p) = @_;
    init_template($p, 'problems_all');
    my $lv = CATS::ListView->new(
        web => $p, name => 'link_problem',
        url => url_f('problems_all', link => $p->{link}, move => $p->{move}));

    $t->param(used_codes => $contest->used_problem_codes) if $p->{link};

    my $where =
        $is_root ? {
            cond => [], params => [] }
        : !$p->{link} ? {
            cond => [ 'CURRENT_TIMESTAMP > C.finish_date AND (C.is_hidden = 0 OR C.is_hidden IS NULL)' ],
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
    my $where_cond = join(' AND ', @{$where->{cond}}) || '1=1';

    my $accepted_sql = qq~SUM(CASE R.state WHEN $cats::st_accepted THEN 1 ELSE 0 END)~;
    my $accepted_orderby = qq~(SELECT $accepted_sql FROM reqs R WHERE R.problem_id = P.id)~;

    $lv->default_sort(0)->define_columns([
        { caption => res_str(602), order_by => 'P.title', width => '30%',
            checkbox => $is_jury && $p->{link} && '[name=problems_selection]' },
        { caption => res_str(619), order_by => 'CP.code', width => '1%', col => 'Co' },
        { caption => res_str(603), order_by => 'C.title', width => '30%' },
        { caption => res_str(604), order_by => $accepted_orderby, width => '10%', col => 'Ok' },
        { caption => res_str(667), order_by => 'keywords', width => '20%', col => 'Kw' },
    ]);
    CATS::Problem::Utils::define_common_searches($lv);
    CATS::Problem::Utils::define_kw_subquery($lv);
    $lv->define_db_searches({
        contest_title => 'C.title',
        ($is_root ? (all_tags => q~
            (SELECT LIST(DISTINCT CP1.tags) FROM contest_problems CP1
                WHERE CP1.problem_id = P.id AND CP1.tags IS NOT NULL)~) : ()),
    });
    $lv->default_searches([ qw(contest_title) ]);
    my $ok_wa_tl = $lv->visible_cols->{Ok} ? qq~
        SELECT
            $accepted_sql || ' / ' ||
            SUM(CASE R.state WHEN $cats::st_wrong_answer THEN 1 ELSE 0 END) || ' / ' ||
            SUM(CASE R.state WHEN $cats::st_time_limit_exceeded THEN 1 ELSE 0 END)
            FROM reqs R WHERE R.problem_id = P.id~ : 'NULL';
    my $keywords = $lv->visible_cols->{Kw} ? q~
        SELECT LIST(DISTINCT K.code, ' ') FROM keywords K
        INNER JOIN problem_keywords PK ON PK.keyword_id = K.id AND PK.problem_id = P.id~ : 'NULL';
    my $sth = $dbh->prepare(qq~
        SELECT
            P.id AS problem_id, P.title, C.title AS contest_title, P.contest_id, CP.code,
            ($ok_wa_tl) AS counts,
            ($keywords) AS keywords,
            (SELECT 1 FROM contest_problems CP1
                WHERE CP1.problem_id = P.id AND CP1.contest_id = ?) AS linked
        FROM problems P INNER JOIN contests C ON C.id = P.contest_id
        INNER JOIN contest_problems CP ON CP.contest_id = C.id AND CP.problem_id = P.id
        WHERE $where_cond ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, @{$where->{params}}, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        my $pid = $row->{problem_id};
        my %pp = (cid => $row->{contest_id}, pid => $pid);
        return (
            href_view_problem => url_f('problem_text', pid => $pid),
            href_view_contest => url_f_cid('problems', cid => $row->{contest_id}),
            # Jury can download package for any problem after linking, but not before.
            ($is_root ? (href_download => url_f_cid('problem_download', %pp)) : ()),
            ($is_root ? (href_problem_details => url_f_cid('problem_details', %pp)) : ()),
            href_problem_console => _href_problem_console($pid),
            %$row,
            linked => $row->{linked} || !$p->{link},
        );
    };

    $lv->attach($fetch_record, $sth);
    $sth->finish;

    my @submenu = !$p->{link} ? () :
        { href => url_f('problems_all',
            search => sprintf('is_used_by_contest(%d)', $cid), link => $p->{link}, move => $p->{move}),
            item => res_str(588) };
    $t->param(
        href_action => url_f('problems'),
        link => !$contest->is_practice && $p->{link},
        move => $p->{move},
        submenu => \@submenu,
    );
}

sub problems_frame_jury_action {
    my ($p) = @_;
    $is_jury or return;

    if ($p->{link_save}) {
        for (@{$p->{problems_selection}}) {
            $p->{move} ?
                CATS::Problem::Save::move_problem($_, $p->{code}, $cid) :
                CATS::Problem::Save::link_problem($_, $p->{code}, $cid);
        }
        return;
    }
    if ($p->{limits_cpid}) {
         my $title = $dbh->selectrow_array(q~
            SELECT P.title FROM problems P
            INNER JOIN contest_problems CP ON CP.problem_id = P.id
            WHERE CP.contest_id = ? AND CP.id = ?~, undef,
            $cid, $p->{limits_cpid});
         msg(1145, $title) if $title;
    }
    $p->{change_status} and return CATS::Problem::Utils::problems_change_status($p);
    $p->{change_code} and return CATS::Problem::Utils::problems_change_code($p);
    $p->{replace} and return CATS::Problem::Save::problems_replace($p, $p->{problem_id});
    $p->{add_new} and return CATS::Problem::Save::problems_add_new($p);
    $p->{add_new_template} and return CATS::Problem::Save::problems_add_template(
        File::Spec->catdir(CATS::Config::cats_dir, 'cats-problem', 'templates', 'minimal'),
        { title => $p->{new_title}, lang => $p->{new_lang} });
    $p->{add_remote} and return CATS::Problem::Save::problems_add_new_remote($p);
    $p->{std_solution} and return CATS::Problem::Submit::problems_submit_std_solution($p);
    CATS::Problem::Storage::delete($p->{delete_problem}) if $p->{delete_problem};
}

sub has_lang_tag {
    my ($problem) = @_;
    $problem->{tags} or return;
    my $parsed_tags =
        eval { CATS::Problem::Tags::parse_tag_condition($problem->{tags}); } or return;
    $parsed_tags->{lang};
}

sub _check_inaccessible {
    if (!$contest->has_started($user->{diff_time})) {
        return 'not_started';
    }
    if ($contest->{local_only} && !$user->{is_local}) {
        return CATS::Contest::Participate::can_start_offset() ? 'can_start_offset' : 'local_only';
    }
}

sub _combine_limits {
    my ($override, $default) = @_;
    defined $override && defined $default ? "$override ($default)" : $override // $default;
}

sub _collect_req_stats {
    my ($aid) = @_;
    my $req_state_vals = join ',', map $CATS::Verdicts::name_to_state->{$_},
        @$CATS::Verdicts::problem_list_stats;
    my $reqs = $dbh->selectall_arrayref(qq~
        SELECT R.problem_id, R.state, COUNT(*) cnt FROM reqs R
        WHERE R.contest_id = ? AND R.account_id = ? AND R.state IN ($req_state_vals)
        GROUP BY R.problem_id, R.state~, { Slice => {} },
        $cid, $aid);
    my $reqs_idx = {};
    for (@$reqs) {
        $reqs_idx->{$_->{problem_id}}->{$CATS::Verdicts::state_to_name->{$_->{state}}} = $_->{cnt};
    }

    my $last_submits = $dbh->selectall_hashref(q~
        SELECT L.problem_id, R1.id, R1.state FROM reqs R1 INNER JOIN (
            SELECT CP.problem_id, MAX(R.submit_time) AS last FROM reqs R
            INNER JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
            WHERE CP.contest_id = ? AND R.account_id = ?
            GROUP BY CP.problem_id) L
        ON R1.problem_id = L.problem_id AND R1.submit_time = L.last AND R1.account_id = ?~,
        'problem_id', { Slice => {} },
        $cid, $aid, $aid);
    ($reqs_idx, $last_submits);
}

sub _proctoring {
    my ($p) = @_;
    $is_root or return;
    my ($params) = $dbh->selectrow_array(q~
        SELECT params FROM proctoring WHERE contest_id = ?~, undef,
        $cid) or return;
    $params = eval { decode_json($params) } or return;
    $params->{type} eq 'examus' or return;
    $params->{$_} or return for qw(secret);
    my $e = CATS::Examus->new(
        (map { $_ => $contest->{$_} } qw(start_date finish_date)),
        (map { $_ => $params->{$_} } qw(secret examus_url integration_name)),
    );
    $t->param(proctoring => {
        url => $e->start_session_url,
        token => $e->make_jws_token,
        payload => $e->payload,
    });
}

sub problems_frame {
    my ($p) = @_;

    unless ($is_jury) {
        if (my $reason = _check_inaccessible) {
            init_template($p, 'problems_inaccessible');
            if ($p->{participate_online}) {
                CATS::Contest::Participate::online;
                $reason = _check_inaccessible;
            }
            if ($p->{start_offset}) {
                CATS::Contest::Participate::start_offset && $p->redirect(url_f 'problems');
            }
            $t->param(
                reason => $reason,
                CATS::Contest::Participate::flags_can_participate,
            );
            return;
        }
    }

    init_template($p, 'problems');
    my $lv = CATS::ListView->new(
        web => $p, name => 'problems' . ($contest->is_practice ? '_practice' : ''),
        array_name => 'problems', url => url_f('problems'));

    problems_frame_jury_action($p);

    CATS::Problem::Submit::problems_submit($p) if $p->{submit};
    CATS::Contest::Participate::online if $p->{participate_online};
    CATS::Contest::Participate::virtual if $p->{participate_virtual};
    _proctoring($p);

    if ($uid && !$is_jury) {
        if ($contest->has_finished_for($user)) {
            msg(1115, $contest->{title});
        }
        elsif (!$user->{is_participant}) {
            msg(1116);
        }
    }

    my $wikis = $dbh->selectall_arrayref(q~
        SELECT CW.id, CW.wiki_id, CW.allow_edit, WP.name, WT.title
        FROM contest_wikis CW
        INNER JOIN wiki_pages WP ON CW.wiki_id = WP.id
        LEFT JOIN wiki_texts WT ON WT.wiki_id = WP.id AND WT.lang = ?
        WHERE CW.contest_id = ?
        ORDER BY CW.ordering, WP.name~, { Slice => {} },
        CATS::Settings::lang, $cid);
    for (@$wikis) {
        $_->{href} = url_f('wiki', name => $_->{name});
        $_->{href_edit} = url_f('contest_wikis_edit', id => $_->{id}) if $is_jury;
    }
    $t->param(wikis => $wikis);

    my $aid = $uid || 0; # in a case of anonymous user

    my $rc_order_by = sprintf qq~
        (SELECT R.state FROM reqs R
            WHERE R.problem_id = P.id AND R.account_id = %d AND R.contest_id = %d
            ORDER BY R.submit_time DESC $CATS::DB::db->{LIMIT} 1)~, $aid, $cid;

    $lv->default_sort(0)->define_columns([
        { caption => res_str(602), order_by => ($contest->is_practice ? 'P.title' : 'CP.code'), width => '25%' },
        ($is_jury ?
        (
            { caption => res_str(622), order_by => 'CP.status', width => '5%' },
            { caption => res_str(605), order_by => 'CP.testsets', width => '12%', col => 'Ts' },
            { caption => res_str(629), order_by => 'CP.tags', width => '5%', col => 'Tg' },
            { caption => res_str(638), order_by => 'job_split_strategy', width => '5%', col => 'St' },
            { caption => res_str(687), order_by => 'max_points', width => '5%', col => 'Mp' },
            { caption => res_str(691), order_by => 'weight', width => '5%', col => 'We' },
            { caption => res_str(688), order_by => 'max_reqs', width => '5%', col => 'Mr' },
            { caption => res_str(811), order_by => 'input_file', width => '5%', col => 'If' },
            { caption => res_str(812), order_by => 'output_file', width => '5%', col => 'Of' },
            { caption => res_str(632), order_by => 'time_limit', width => '5%', col => 'Tl' },
            { caption => res_str(628), order_by => 'memory_limit', width => '5%', col => 'Ml' },
            { caption => res_str(617), order_by => 'write_limit', width => '5%', col => 'Wl' },
            { caption => res_str(667), order_by => 'keywords', width => '10%', col => 'Kw' },
            { caption => res_str(635), order_by => 'last_modified_by_name', width => '5%', col => 'Mu' },
            { caption => res_str(634), order_by => 'P.upload_date', width => '10%', col => 'Mt' },
            { caption => res_str(641), order_by => 'allow_des', width => '5%', col => 'Ad' },
            { caption => res_str(618), order_by => 'judges', width => '5%', col => 'Ju' },
            { caption => res_str(698), order_by => 'snippets', width => '5%', col => 'Sn' },
            { caption => res_str(675), col => 'Cl' },
        )
        : ()
        ),
        ($contest->is_practice ?
        { caption => res_str(603), order_by => 'contest_title', width => '15%' } : ()
        ),
        { caption => res_str(604), order_by => $rc_order_by, width => '12%', col => 'Vc' }, # ok/wa/tl
    ]);
    CATS::Problem::Utils::define_common_searches($lv);
    if ($is_jury || $contest->has_finished_for($user)) {
        CATS::Problem::Utils::define_kw_subquery($lv);
        $lv->define_subqueries({ has_tag => q~(POSITION(?, CP.tags) > 0)~ });
    }
    $lv->define_db_searches({ contest_title => 'OC.title' });
    my $psn = CATS::Problem::Utils::problem_status_names_enum($lv);

    my ($req_stats_idx, $last_submits) = $lv->visible_cols->{Vc} ? _collect_req_stats($aid) : ({}, {});

    my $select_code = $contest->is_practice ? 'NULL' : 'CP.code';
    my $hidden_problems = $is_jury ? '' : " AND CP.status < $cats::problem_st_hidden";
    my $original_contest_code_sql = $is_jury ? q~
        (SELECT OCP.code FROM contest_problems OCP
        WHERE OCP.problem_id = P.id AND OCP.contest_id = P.contest_id)~ : 'NULL';
    # TODO: take testsets into account
    my $test_count_sql = $is_jury ?
        '(SELECT COUNT(*) FROM tests T WHERE T.problem_id = P.id) AS test_count,' : '';
    my $limits_str = join ', ', map "P.$_, L.$_ AS cp_$_", @cats::limits_fields;
    my $keywords = $is_jury && $lv->visible_cols->{Kw} ? q~(
        SELECT LIST(DISTINCT K.code, ' ') FROM keywords K
        INNER JOIN problem_keywords PK ON PK.keyword_id = K.id AND PK.problem_id = P.id
        ) AS keywords,~ : '';
    my $allow_des = $is_jury && $lv->visible_cols->{Ad} ? q~(
        SELECT LIST(DISTINCT D.code, ' ') FROM default_de D
        INNER JOIN contest_problem_des CPD ON CPD.cp_id = CP.id AND CPD.de_id = D.id
        ORDER BY 1
        ) AS allow_des, (
        SELECT LIST(DISTINCT D.description, ' ') FROM default_de D
        INNER JOIN contest_problem_des CPD ON CPD.cp_id = CP.id AND CPD.de_id = D.id
        ORDER BY 1
        ) AS allow_des_names,~ : '';
    # Use result_time to account for re-testing standard solutions,
    # but also limit by sumbit_time to speed up since there is no index on result_time.
    my $judges_installed_sql = $is_jury && $lv->visible_cols->{Ju} ? qq~
        (SELECT COUNT(DISTINCT R.judge_id) FROM reqs R
        WHERE R.problem_id = P.id AND R.state > $cats::request_processed AND
            R.result_time > P.upload_date AND R.submit_time > P.upload_date - 30)~ :
        'NULL';
    my $job_split_strategy_sql = $is_jury && $lv->visible_cols->{St} ? q~
        (SELECT L.job_split_strategy FROM limits L WHERE L.id = CP.limits_id)~ : 'NULL';
    my $snippets_sql = $is_jury && $lv->visible_cols->{Sn} ?
        join ', ', map sprintf('(%s) AS %s', $lv->qb->get_db_search($_), $_),
            qw(problem_snippets snippets) :
        'NULL AS problem_snippets, NULL AS snippets';

    my $child_contests = $dbh->selectall_arrayref(q~
        SELECT id, title FROM contests C WHERE C.parent_id = ? AND C.is_hidden = 0~, { Slice => {} },
        $cid);
    my %child_contests_idx;
    $child_contests_idx{$_->{id}} = $_ for @$child_contests;
    my ($contests_sql, @contests_params) =
        $sql->where({ 'CP.contest_id' => [ $cid, map $_->{id}, @$child_contests ] });

    # Concatenate last submission fields to work around absence of tuples.
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            P.input_file, P.output_file,
            $select_code AS code, P.title, OC.title AS contest_title,
            $original_contest_code_sql AS original_code,
            $keywords
            $allow_des
            P.contest_id - CP.contest_id AS is_linked,
            (SELECT COUNT(*) FROM contest_problems CP1
                WHERE CP1.contest_id <> CP.contest_id AND CP1.problem_id = P.id) AS usage_count,
            OC.id AS original_contest_id, CP.status,
            P.upload_date, $judges_installed_sql AS judges_installed,
            P.last_modified_by,
            (SELECT A.login FROM accounts A WHERE A.id = P.last_modified_by) AS last_modified_by_name,
            SUBSTRING(P.explanation FROM 1 FOR 1) AS has_explanation,
            $test_count_sql CP.testsets, CP.points_testsets, P.lang,
            $limits_str, L.job_split_strategy,
            $snippets_sql,
            CP.max_points, CP.scaled_points, CP.round_points_to, CP.weight, CP.is_extra,
            P.repo, CP.tags, P.statement_url, P.explanation_url, CP.color, CP.max_reqs,
            CP.contest_id
        FROM problems P
        INNER JOIN contest_problems CP ON CP.problem_id = P.id
        INNER JOIN contests OC ON OC.id = P.contest_id
        INNER JOIN contests CC ON CC.id = CP.contest_id
        LEFT JOIN limits L ON L.id = CP.limits_id
        $contests_sql$hidden_problems~ .
        $lv->maybe_where_cond . $lv->order_by('CC.start_date')
    );
    $sth->execute(@contests_params, $lv->where_params);

    my @status_list;
    if ($is_jury) {
        my $n = CATS::Messages::problem_status_names();
        for (sort keys %$n) {
            push @status_list, { id => $_, name => $n->{$_} };
        }
        $t->param(status_list => \@status_list, editable => 1);
    }

    my $text_link_f =
        $is_jury || $contest->{is_hidden} || $contest->{local_only} || $contest->{time_since_start} < 0 ?
        \&url_f : \&CATS::StaticPages::url_static;
    my %any_langs;

    my $prev_contest = 0;

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
        my $problem_langs = [];
        my $lang_tag = has_lang_tag($c);
        if (!$hrefs_view{statement} && ($is_jury || !$lang_tag)) {
            my @langs = split ',', $c->{lang};
            $problem_langs = [ map
                +{ name => $_, href => $text_link_f->('problem_text', cpid => $c->{cpid}, pl => $_) },
                @langs[1 .. $#langs]
            ];
            @any_langs{@langs} = undef;
        }
        $any_langs{$lang_tag->[1] // $c->{lang}} = undef if !@$problem_langs && !$hrefs_view{statement};

        my $last_request = $last_submits->{$c->{pid}}->{id};
        my $last_state = $last_submits->{$c->{pid}}->{state} // 0;
        my $last_verdict = do {
            my $lastv = $last_state ? $CATS::Verdicts::state_to_name->{$last_state} : '';
            CATS::Verdicts::hide_verdict_self($is_jury, $lastv);
        };

        my $can_download = CATS::Problem::Utils::can_download_package;
        my $max_points = $c->{max_points} // '*';

        my $group_title =
            $c->{contest_id} == $prev_contest ? '' : $child_contests_idx{$c->{contest_id}}->{title};
        my $href_group = $group_title && url_f_cid('problems', cid => $c->{contest_id});
        $prev_contest = $c->{contest_id};

        my $rc = $req_stats_idx->{$c->{pid}} // {};
        return (
            href_delete => url_f('problems', delete_problem => $c->{cpid}),
            href_change_status => url_f('problems', change_status => $c->{cpid}),
            href_change_code => url_f('problems', change_code => $c->{cpid}),
            href_replace  => url_f('problems', replace => $c->{cpid}),
            href_download => $can_download && url_f('problem_download', pid => $c->{pid}),
            href_problem_details => $is_jury && url_f('problem_details', pid => $c->{pid}),
            href_original_contest => url_f_cid('problems', cid => $c->{original_contest_id}),
            href_usage => url_f('contests', search => "has_problem($c->{pid})", filter => 'all'),
            href_problem_console => _href_problem_console($c->{pid}),
            href_select_testsets => url_f('problem_select_testsets', pid => $c->{pid}, from_problems => 1),
            href_select_tags => url_f('problem_select_tags', pid => $c->{pid}, from_problems => 1),
            href_select_strategy => url_f('problem_limits', pid => $c->{pid}, from_problems => 1),
            href_last_request => ($last_request ? url_f('run_details', rid => $last_request) : ''),
            href_allow_des => url_f('problem_des', pid => $c->{pid}),
            href_problem_limits => $is_jury && url_f('problem_limits', pid => $c->{pid}, from_problems => 1),
            href_judges_installed => $is_jury &&
                url_f('contest_problems_installed', search => 'problem_id=' . $c->{pid}),
            href_snippets => $is_jury &&
                url_f('snippets', search => "problem_id=$c->{pid},contest_id=$c->{contest_id}"),

            status => $c->{status},
            status_text => $psn->{$c->{status}},
            disabled => !$is_jury && $c->{contest_id} == $cid &&
                ($c->{status} >= $cats::problem_st_disabled || $last_state == $cats::st_banned),
            href_view_problem =>
                $hrefs_view{statement} || $text_link_f->('problem_text', cpid => $c->{cpid}),
            problem_langs => $problem_langs,
            href_explanation => ($is_jury || $contest->{show_explanations}) && $c->{has_explanation} ?
                $hrefs_view{explanation} || url_f('problem_text', cpid => $c->{cpid}, explain => 1) : '',
            problem_id => $c->{pid},
            cpid => $c->{cpid},
            selected => $c->{pid} == ($p->{problem_id} || 0),
            code => $c->{code},
            title => $c->{title},
            original_code => $c->{original_code},
            is_linked => $c->{is_linked},
            remote_url => $remote_url,
            usage_count => $c->{usage_count},
            original_contest_id => $c->{original_contest_id},
            contest_title => $c->{contest_title},
            reqs_count => sprintf('%s + %s / %s / %s', map $_ // '0', @$rc{qw(OK AW WA TL)}),
            upload_date => $c->{upload_date},
            upload_date_iso => $c->{upload_date},
            judges_installed => $c->{judges_installed},
            last_modified_by => $c->{last_modified_by},
            last_modified_by_name => $c->{last_modified_by_name},
            testsets => $c->{testsets} || '*',
            points_testsets => $c->{points_testsets},
            test_count => $c->{test_count},
            input_file => $c->{input_file},
            output_file => $c->{output_file},
            snippets => $c->{snippets},
            problem_snippets => $c->{problem_snippets},
            memory_limit => _combine_limits($c->{cp_memory_limit}, $c->{memory_limit}),
            time_limit => _combine_limits($c->{cp_time_limit}, $c->{time_limit}),
            write_limit => _combine_limits($c->{cp_write_limit}, $c->{write_limit}) // '*',
            max_points => _combine_limits($c->{scaled_points} && (0 + $c->{scaled_points}), $max_points) .
                ($c->{round_points_to} ? ' ~' . (0 + $c->{round_points_to}) : ''),
            weight => $c->{weight} ? 0 + $c->{weight} : '*',
            is_extra => $c->{is_extra},
            tags => $c->{tags},
            strategy => $c->{job_split_strategy} // '*',
            max_reqs => $c->{max_reqs} // '*',
            last_verdict => $last_verdict,
            keywords => $c->{keywords},
            allow_des => $c->{allow_des} // '*',
            allow_des_names => $c->{allow_des_names} // '',
            color => $c->{color},
            group_title => $group_title,
            href_group => $href_group,
        );
    };
    $lv->date_fields(qw(upload_date))->date_fields_iso(qw(upload_date_iso));

    $lv->attach($fetch_record, $sth);

    $sth->finish;

    my ($jactive) = CATS::Judge::get_active_count;

    my $pt_url = sub {
        my ($href, $item, $tf) = @_;
        $item //= res_str(538);
        $tf //= $text_link_f;
        {
            href => $tf->(@$href), item => $item,
            keys %any_langs < 2 ? () : (sub_items => [
                map +{ href => $tf->(@$href, pl => $_), item => $_ }, sort keys %any_langs ])
        }
    };
    my $pr = $contest->is_practice;
    my @submenu = grep $_,
        ($is_jury ? (
            !$pr && $pt_url->([ 'problem_text',
                nospell => 1, nokw => 1, notime => 1, noformal => 1,
                noauthor => 1, nosubmit => 1, nonav => 1 ]),
            !$pr && $pt_url->([ 'problem_text' ], res_str(555)),
            $is_jury && !$pr && $pt_url->(
                [ 'problem_text', cid => $cid ], res_str(515), \&CATS::StaticPages::url_static),
            { href => url_f('problems_all', link => 1), item => res_str(540) },
            { href => url_f('problems_all', link => 1, move => 1), item => res_str(551) },
            !$pr && ({ href => url_f('problems_retest'), item => res_str(556) }),
            { href => url_f('contests_prizes', clist => $cid), item => res_str(565) },
        )
        : (
            !$pr && $pt_url->([ 'problem_text', cid => $cid, nosubmit => 1 ]),
            !$pr && $pt_url->([ 'problem_text', cid => $cid ], res_str(555)),
        )),
        { href => url_f('contest_params', id => $cid), item => res_str(594) };

    my $parent_contest = $dbh->selectrow_hashref(q~
        SELECT C1.title, C1.id, C1.short_descr
        FROM contests C1 INNER JOIN contests C ON C1.id = C.parent_id
        WHERE C.id = ?~, undef,
        $cid);
    if ($parent_contest) {
        $parent_contest->{href} = url_f_cid('problems', cid => $parent_contest->{id});
    }

    $t->param(
        href_login => url_f('login', redir => CATS::Redirect::pack_params($p)),
        href_set_problem_color => url_f('set_problem_color'),
        href_find_users => url_f('api_find_users', in_contest => $cid),
        CATS::Contest::Participate::flags_can_participate,
        submenu => \@submenu, title_suffix => res_str(525),
        is_user => $uid,
        can_submit => CATS::Problem::Submit::can_submit,
        CATS::Problem::Submit::prepare_de_list($p),
        contest_id => $cid, no_judges => !$jactive,
        parent_contest => $parent_contest,
        source_text => $p->{source_text},
        no_listview_header => !$is_jury && !$lv->total_row_count && ($lv->settings->{search} // '') eq '',
        child_contest_count => scalar @$child_contests,
        href_child_contests =>
            @$child_contests && url_f('contests', search => "parent_or_id=$cid", filter=> 'all'),
     );
}

sub problem_text_frame { goto \&CATS::Problem::Text::problem_text }

sub submit_problem_api {
    my ($p) = @_;
    my ($rid, $result) = CATS::Problem::Submit::problems_submit($p);
    $p->print_json({
        messages => CATS::Messages::get,
        status => $rid ? 'ok' : 'error',
        $result ? %$result : () });
}

sub set_problem_color {
    my ($p) = @_;
    $p->{cpid} && $p->{color} && $is_jury
        or return $p->print_json({ result => 'error' });

    $p->{color} = undef if $p->{color} eq '#000000';
    $dbh->do(q~
        UPDATE contest_problems SET color = ?
        WHERE contest_id = ? AND id = ?~, undef,
        $p->{color}, $cid, $p->{cpid});
    $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $p->{cpid});
    $p->print_json({ result => 'ok' });
}

1;
