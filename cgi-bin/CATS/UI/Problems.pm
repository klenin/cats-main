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
use CATS::Output qw(init_template url_f);
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
use CATS::Utils qw(file_type date_to_iso redirect_url_function url_function);
use CATS::Verdicts;

sub problems_all_frame {
    my ($p) = @_;
    init_template($p, 'problems_all.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'link_problem');

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

    $lv->define_columns(url_f('problems_all', link => $p->{link}), 0, 0, [
        { caption => res_str(602), order_by => 'P.title', width => '30%' },
        { caption => res_str(603), order_by => 'C.title', width => '30%' },
        { caption => res_str(604), order_by => 'ok_wa_tl', width => '10%', col => 'Ok' },
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
    my $ok_wa_tl = $lv->visible_cols->{Ok} ? qq~
        SELECT
            SUM(CASE R.state WHEN $cats::st_accepted THEN 1 ELSE 0 END) || ' / ' ||
            SUM(CASE R.state WHEN $cats::st_wrong_answer THEN 1 ELSE 0 END) || ' / ' ||
            SUM(CASE R.state WHEN $cats::st_time_limit_exceeded THEN 1 ELSE 0 END)
            FROM reqs R WHERE R.problem_id = P.id~ : 'NULL';
    my $keywords = $lv->visible_cols->{Kw} ? q~
        SELECT LIST(DISTINCT K.code, ' ') FROM keywords K
        INNER JOIN problem_keywords PK ON PK.keyword_id = K.id AND PK.problem_id = P.id~ : 'NULL';
    my $c = $dbh->prepare(qq~
        SELECT
            P.id, P.title, C.title, C.id,
            ($ok_wa_tl) AS ok_wa_tl,
            ($keywords) AS keywords,
            (SELECT COUNT(*) FROM contest_problems CP WHERE CP.problem_id = P.id AND CP.contest_id = ?)
        FROM problems P INNER JOIN contests C ON C.id = P.contest_id
        INNER JOIN contest_problems CP ON CP.contest_id = C.id AND CP.problem_id = P.id
        WHERE $where_cond ~ . $lv->maybe_where_cond . $lv->order_by);
    $c->execute($cid, @{$where->{params}}, $lv->where_params);

    my $fetch_record = sub {
        my ($pid, $title, $contest_title, $contest_id, $counts, $keywords, $linked) = $_[0]->fetchrow_array
            or return ();
        my %pp = (sid => $sid, cid => $contest_id, pid => $pid);
        return (
            href_view_problem => url_f('problem_text', pid => $pid),
            href_view_contest => url_function('problems', sid => $sid, cid => $contest_id),
            # Jury can download package for any problem after linking, but not before.
            ($is_root ? (href_download => url_function('problem_download', %pp)) : ()),
            ($is_jury ? (href_problem_history => url_function('problem_history', %pp)) : ()),
            keywords => $keywords,
            linked => $linked || !$p->{link},
            problem_id => $pid,
            title => $title,
            contest_title => $contest_title,
            counts => $counts,
        );
    };

    $lv->attach(url_f('problems_all', link => $p->{link}, move => $p->{move}), $fetch_record, $c);
    $c->finish;

    $t->param(
        href_action => url_f('problems'),
        link => !$contest->is_practice && $p->{link}, move => $p->{move});
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
    $p->{change_status} and return CATS::Problem::Utils::problems_change_status($p);
    $p->{change_code} and return CATS::Problem::Utils::problems_change_code($p);
    $p->{replace} and return CATS::Problem::Save::problems_replace($p, $p->{problem_id});
    $p->{add_new} and return CATS::Problem::Save::problems_add_new($p);
    $p->{add_new_template} and return CATS::Problem::Save::problems_add_template(
        File::Spec->catdir(CATS::Config::cats_dir, 'cats-problem', 'templates', 'minimal'),
        { title => Encode::decode_utf8($p->{new_title}), lang => $p->{new_lang} });
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

sub _prepare_de_list {
    my $de_list =
        CATS::DevEnv->new(CATS::JudgeDB::get_DEs({ active_only => 1, fields => 'syntax' }));

    my ($allowed_des) = $dbh->selectall_arrayref(_u $sql->select(
        'contest_problems CP LEFT JOIN contest_problem_des CPD ON CP.id = CPD.cp_id',
        'CP.id, CPD.de_id',
        { 'CP.contest_id' => $cid,
            ($is_jury ? () : ('CP.status' => { '<', $cats::problem_st_disabled })) }
    ));

    my $allow_all = 0;
    my %allowed;
    for (@$allowed_des) {
        if($_->{de_id}) {
            $allowed{$_->{de_id}} = 1;
        }
        else {
            $allow_all = 1;
            last;
        }
    }

    my @all_des = $allow_all ? @{$de_list->des} : grep $allowed{$_->{id}}, @{$de_list->des};
    my @de = (
        { de_id => 'by_extension', de_name => res_str(536) },
         map {{ de_id => $_->{id}, de_name => $_->{description}, syntax => $_->{syntax} }} @all_des );
    (de_list => \@de, (@all_des == 1 ? (de_selected => $all_des[0]->{id}) : ()));
}

sub problems_frame {
    my ($p) = @_;

    my $show_packages = 1;
    unless ($is_jury) {
        $show_packages = $contest->{show_packages};
        if (!$contest->has_started($user->{diff_time})) {
            init_template($p, 'problems_inaccessible');
            return msg(1130);
        }
        if ($contest->{local_only} && !$user->{is_local}) {
            init_template($p, 'problems_inaccessible');
            $t->param(local_only => 1);
            return;
        }
    }

    init_template($p, 'problems');
    my $lv = CATS::ListView->new(
        web => $p, name => 'problems' . ($contest->is_practice ? '_practice' : ''),
        array_name => 'problems');

    problems_frame_jury_action($p);

    CATS::Problem::Submit::problems_submit($p) if $p->{submit};
    CATS::Contest::Participate::online if $p->{participate_online};
    CATS::Contest::Participate::virtual if $p->{participate_virtual};

    my $wikis = $dbh->selectall_arrayref(q~
        SELECT CW.wiki_id, CW.allow_edit, WP.name, WT.title
        FROM contest_wikis CW
        INNER JOIN wiki_pages WP ON CW.wiki_id = WP.id
        LEFT JOIN wiki_texts WT ON WT.wiki_id = WP.id AND WT.lang = ?
        WHERE CW.contest_id = ?
        ORDER BY CW.ordering, WP.name~, { Slice => {} },
        CATS::Settings::lang, $cid);
    $_->{href} = url_f('wiki', name => $_->{name}) for @$wikis;
    $t->param(wikis => $wikis);

    my @cols = (
        { caption => res_str(602), order_by => ($contest->is_practice ? 'P.title' : 3), width => '25%' },
        ($is_jury ?
        (
            { caption => res_str(622), order_by => 'CP.status', width => '8%' },
            { caption => res_str(605), order_by => 'CP.testsets', width => '12%', col => 'Ts' },
            { caption => res_str(629), order_by => 'CP.tags', width => '8%', col => 'Tg' },
            { caption => res_str(667), order_by => 'keywords', width => '10%', col => 'Kw' },
            { caption => res_str(635), order_by => 'last_modified_by', width => '5%', col => 'Mu' },
            { caption => res_str(634), order_by => 'P.upload_date', width => '10%', col => 'Mt' },
            { caption => res_str(641), order_by => 'allow_des', width => '5%', col => 'Ad' },
            { caption => res_str(675), col => 'Cl' },
        )
        : ()
        ),
        ($contest->is_practice ?
        { caption => res_str(603), order_by => '5', width => '15%' } : () # contest
        ),
        { caption => res_str(604), order_by => '6', width => '12%', col => 'Vc' }, # ok/wa/tl
    );
    $lv->define_columns(url_f('problems'), 0, 0, \@cols);
    CATS::Problem::Utils::define_common_searches($lv);
    if ($is_jury || $contest->has_finished_for($user)) {
        CATS::Problem::Utils::define_kw_subquery($lv);
        $lv->define_subqueries({ has_tag => q~(POSITION(?, CP.tags) > 0)~ });
    }
    $lv->define_db_searches({ contest_title => 'OC.title' });
    my $psn = CATS::Problem::Utils::problem_status_names_enum($lv);

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
            WHERE R.problem_id = P.id AND R.account_id = ? AND R.contest_id = ?
            ORDER BY R.submit_time DESC ROWS 1) AS last_submission~
    : q~
        NULL AS accepted_count,
        NULL AS wrong_answer_count,
        NULL AS time_limit_count,
        NULL AS last_submission~;
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
    my $judges_installed_sql = $is_jury && $lv->visible_cols->{Vc} ? qq~
        (SELECT COUNT(DISTINCT R.judge_id) FROM reqs R
        WHERE R.problem_id = P.id AND R.state > $cats::request_processed AND
            R.result_time > P.upload_date AND R.submit_time > P.upload_date - 30)~ :
        'NULL';

    # Concatenate last submission fields to work around absence of tuples.
    my $sth = $dbh->prepare(qq~
        SELECT
            CP.id AS cpid, P.id AS pid,
            $select_code AS code, P.title, OC.title AS contest_title,
            $counts,
            $keywords
            $allow_des
            P.contest_id - CP.contest_id AS is_linked,
            (SELECT COUNT(*) FROM contest_problems CP1
                WHERE CP1.contest_id <> CP.contest_id AND CP1.problem_id = P.id) AS usage_count,
            OC.id AS original_contest_id, CP.status,
            P.upload_date, $judges_installed_sql AS judges_installed,
            (SELECT A.login FROM accounts A WHERE A.id = P.last_modified_by) AS last_modified_by,
            SUBSTRING(P.explanation FROM 1 FOR 1) AS has_explanation,
            $test_count_sql CP.testsets, CP.points_testsets, P.lang, $limits_str,
            CP.max_points, P.repo, CP.tags, P.statement_url, P.explanation_url, CP.color
        FROM problems P
        INNER JOIN contest_problems CP ON CP.problem_id = P.id
        INNER JOIN contests OC ON OC.id = P.contest_id
        WHERE CP.contest_id = ?$hidden_problems
        ~ . $lv->maybe_where_cond . $lv->order_by
    );
    my $aid = $uid || 0; # in a case of anonymous user
    my @params =
        !$lv->visible_cols->{Vc} ? () :
        $contest->is_practice ? ($aid, $cid) :
        (($aid) x 4, $cid);
    $sth->execute(@params, $cid, $lv->where_params);

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

        my ($last_request, $last_state) = split ' ', $c->{last_submission} || '';
        my $last_verdict = do {
            my $lv = $last_state ? $CATS::Verdicts::state_to_name->{$last_state} : '';
            CATS::Verdicts::hide_verdict_self($is_jury, $lv);
        };

        my $can_download = CATS::Problem::Utils::can_download_package;

        return (
            href_delete => url_f('problems', delete_problem => $c->{cpid}),
            href_change_status => url_f('problems', change_status => $c->{cpid}),
            href_change_code => url_f('problems', change_code => $c->{cpid}),
            href_replace  => url_f('problems', replace => $c->{cpid}),
            href_download => $can_download && url_f('problem_download', pid => $c->{pid}),
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
            href_allow_des => url_f('problem_des', pid => $c->{pid}),

            show_packages => $show_packages,
            status => $c->{status},
            status_text => $psn->{$c->{status}},
            disabled => !$is_jury && $c->{status} == $cats::problem_st_disabled,
            href_view_problem => $hrefs_view{statement} || $text_link_f->('problem_text', cpid => $c->{cpid}),
            problem_langs => $problem_langs,
            href_explanation => $show_packages && $c->{has_explanation} ?
                $hrefs_view{explanation} || url_f('problem_text', cpid => $c->{cpid}, explain => 1) : '',
            problem_id => $c->{pid},
            cpid => $c->{cpid},
            selected => $c->{pid} == ($p->{problem_id} || 0),
            code => $c->{code},
            title => $c->{title},
            is_linked => $c->{is_linked},
            remote_url => $remote_url,
            usage_count => $c->{usage_count},
            contest_title => $c->{contest_title},
            accept_count => $c->{accepted_count},
            wa_count => $c->{wrong_answer_count},
            tle_count => $c->{time_limit_count},
            upload_date => $c->{upload_date},
            upload_date_iso => date_to_iso($c->{upload_date}),
            judges_installed => $c->{judges_installed},
            last_modified_by => $c->{last_modified_by},
            testsets => $c->{testsets} || '*',
            points_testsets => $c->{points_testsets},
            test_count => $c->{test_count},
            memory_limit => $c->{memory_limit} * 1024 * 1024,
            time_limit => $c->{time_limit},
            write_limit => $c->{write_limit},
            max_points => $c->{max_points},
            tags => $c->{tags},
            last_verdict => $last_verdict,
            keywords => $c->{keywords},
            allow_des => $c->{allow_des} // '*',
            allow_des_names => $c->{allow_des_names} // '',
            color => $c->{color},
        );
    };

    $lv->attach(url_f('problems'), $fetch_record, $sth);

    $sth->finish;

    my ($jactive) = CATS::Judge::get_active_count;

    my $pt_url = sub {
        my ($href, $item) = @_;
        $item //= res_str(538);
        {
            href => $text_link_f->(@$href), item => $item,
            keys %any_langs < 2 ? () : (sub_items => [
                map +{ href => $text_link_f->(@$href, pl => $_), item => $_ }, sort keys %any_langs ])
        }
    };
    my $pr = $contest->is_practice;
    my @submenu = grep $_,
        ($is_jury ? (
            !$pr && $pt_url->([ 'problem_text',
                nospell => 1, nokw => 1, notime => 1, noformal => 1, noauthor => 1 ]),
            !$pr && $pt_url->([ 'problem_text' ], res_str(555)),
            { href => url_f('problems_all', link => 1), item => res_str(540) },
            { href => url_f('problems_all', link => 1, move => 1), item => res_str(551) },
            !$pr && ({ href => url_f('problems_retest'), item => res_str(556) }),
            { href => url_f('contests_prizes', clist => $cid), item => res_str(565) },
        )
        : (
            !$pr && $pt_url->([ 'problem_text', cid => $cid ]),
        )),
        { href => url_f('contest_params', id => $cid), item => res_str(594) };

    $t->param(
        href_login => url_f('login', redir => CATS::Redirect::pack_params($p)),
        href_set_problem_color => url_f('set_problem_color'),
        CATS::Contest::Participate::flags_can_participate,
        submenu => \@submenu, title_suffix => res_str(525),
        is_user => $uid,
        can_submit => $is_jury ||
            $user->{is_participant} &&
            ($user->{is_virtual} || !$contest->has_finished_for($user)),
        _prepare_de_list(),
        contest_id => $cid, no_judges => !$jactive,
     );
}

sub problem_text_frame { goto \&CATS::Problem::Text::problem_text }

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
