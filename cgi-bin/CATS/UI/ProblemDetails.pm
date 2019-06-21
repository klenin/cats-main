package CATS::UI::ProblemDetails;

use strict;
use warnings;

use File::stat;
use List::Util qw(sum);

use CATS::BinaryFile;
use CATS::Constants;
use CATS::DB;
use CATS::DeGrid;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(downloads_path downloads_url init_template url_f);
use CATS::Problem::Save;
use CATS::Problem::Storage;
use CATS::Problem::Tags;
use CATS::Problem::Text;
use CATS::Problem::Utils;
use CATS::Settings;
use CATS::StaticPages;
use CATS::Testset;
use CATS::Utils qw(url_function);
use CATS::Verdicts;

sub get_request_count {
    my ($this_contest_only, $pid) = @_;
    my $contest_cond = $this_contest_only ? ' AND R.contest_id = ?' : '';
    my $rc = { map { $_->[0] => $_->[1] } @{$dbh->selectall_arrayref(qq~
        SELECT R.state, COUNT(*) AS cnt FROM reqs R
        WHERE R.problem_id = ?$contest_cond GROUP BY R.state~, undef,
        $pid, ($this_contest_only ? $cid : ())
    )} };
    $rc->{total} = sum 0, values %$rc;
    $rc;
}

sub problem_details_frame {
    my ($p) = @_;
    init_template($p, 'problem_details.html.tt');
    $is_jury && $p->{pid} or return;
    my $pr = $dbh->selectrow_hashref(q~
        SELECT
            P.title, P.lang, P.contest_id, P.author, P.last_modified_by, P.upload_date,
            P.run_method, P.save_input_prefix, P.save_answer_prefix, P.save_output_prefix,
            P.time_limit, P.memory_limit, P.write_limit, P.repo_path,
            L.time_limit AS overridden_time_limit,
            L.memory_limit AS overridden_memory_limit,
            L.write_limit as overridden_write_limit,
            C.title AS contest_name, A.team_name,
            CP.id AS cpid, CP.testsets, CP.points_testsets, CP.tags,
            (SELECT COUNT(*) FROM problem_snippets PS
                WHERE PS.problem_id = P.id) AS snippets_declared,
            (SELECT COUNT(*) FROM snippets S
                WHERE S.problem_id = P.id AND S.contest_id = CP.contest_id) AS snippets_generated
        FROM problems P
        INNER JOIN contests C ON C.id = P.contest_id
        INNER JOIN contest_problems CP ON CP.problem_id = P.id AND CP.contest_id = ?
        LEFT JOIN accounts A ON A.id = P.last_modified_by
        LEFT JOIN limits L ON L.id = CP.limits_id
        WHERE P.id = ?~, { Slice => {} },
        $cid, $p->{pid}) or return;

    CATS::Problem::Utils::round_time_limit($pr->{overridden_time_limit});

    my $kw_lang = "name_" . (CATS::Settings::lang eq 'ru' ? 'ru' : 'en');
    $pr->{keywords} = $dbh->selectall_arrayref(qq~
        SELECT K.id, K.code, K.$kw_lang AS name
        FROM keywords K INNER JOIN problem_keywords PK ON PK.keyword_id = K.id
        WHERE PK.problem_id = ? ORDER BY K.code~, { Slice => {} },
        $p->{pid});
    if ($is_root) {
        $_->{href} = url_f('keywords_edit', id => $_->{id}) for @{$pr->{keywords}};
    }

    my ($rc_all, $rc_contest);
    $rc_all = get_request_count(0, $p->{pid}) if $is_root;
    $rc_contest = get_request_count(1, $p->{pid});

    my $make_rc = sub {
        my ($short, $name, $st, $state_search) = @_;
        my $search = "problem_id=$p->{pid}" . ($state_search ? ",state=$state_search" : '');
        my %p = (se => 'problem', i_value => -1, show_results => 1);
        {
            short => $short,
            name => $name,
            all => $rc_all->{$st},
            contest => $rc_contest->{$st},
            href_all => url_f('console', search => $search, %p),
            href_contest => url_f('console', search => "$search,contest_id=$cid", %p),
        }
    };
    $pr->{request_count} = [
        (map {
            my ($n, $st) = @$_;
            $rc_all->{$st} || $rc_contest->{$st} ? $make_rc->($n, $n, $st, $n) : ();
        } @$CATS::Verdicts::name_to_state_sorted),
        $make_rc->('total', res_str(581), 'total'),
    ];

    my @text = ('problem_text', cpid => $pr->{cpid});

    my $text_hrefs = sub {{
        name => $_[0],
        href => {
            full_text => url_f(@text, pl => $_[0]),
            nospell_text => url_f(@text, nospell => 1, pl => $_[0]),
            nomath_text => url_f(@text, nomath => 1, pl => $_[0]),
            ($contest->{is_hidden} || $contest->{local_only} || $contest->{time_since_start} <= 0 ? () :
                (static_text => CATS::StaticPages::url_static(@text, pl => $_[0]))
            ),
        },
    }};
    $pr->{commit_sha} = eval { CATS::Problem::Storage::get_latest_master_sha($p->{pid}); } || 'error';
    warn $@ if $@;
    $t->param(
        p => $pr,
        problem_title => $pr->{title},
        title_suffix => $pr->{title},
        href_modifier => url_f('users_edit', uid => $pr->{last_modified_by}),
        href_edit => url_f('problem_history_tree', pid => $p->{pid}, hb => $pr->{commit_sha}),
        href_edit_xml => url_f('problem_history_edit', pid => $p->{pid}, hb => $pr->{commit_sha}, file => '*'),
        href_original_contest => url_function('problems', cid => $pr->{contest_id}, sid => $sid),
        href_download => url_f('problem_download', pid => $p->{pid}),
        href_git_package => url_f('problem_git_package', pid => $p->{pid}),
        problem_langs => [ map $text_hrefs->($_), undef, split ',', $pr->{lang} ],
        href_text => url_f(@text),
        href_nospell_text => url_f(@text, nospell => 1),
        href_nomath_text => url_f(@text, nomath => 1),
        ($contest->{is_hidden} || $contest->{local_only} || $contest->{time_since_start} <= 0 ? () :
            (href_static_text => CATS::StaticPages::url_static(@text))),
        href_testsets => url_f('problem_select_testsets', pid => $p->{pid}),
        href_test_data => url_f('problem_test_data', pid => $p->{pid}),
        href_problem_limits => url_f('problem_limits', pid => $p->{pid}),
        href_tags => url_f('problem_select_tags', pid => $p->{pid}),
        href_snippets => url_f('snippets', search => "problem_id=$p->{pid},contest_id=$cid"),
    );
    CATS::Problem::Utils::problem_submenu('problem_details', $p->{pid});
}

sub problem_download {
    my ($p) = @_;
    my $pid = $p->{pid} or return $p->not_found;
    CATS::Problem::Utils::can_download_package or return $p->not_found;
    # If hash is non-empty, redirect to existing file.
    # Package size is supposed to be large enough to warrant a separate query.
    my ($hash, $status) = $dbh->selectrow_array(q~
        SELECT P.hash, CP.status FROM problems P
        INNER JOIN contest_problems CP ON cp.problem_id = P.id
        WHERE CP.contest_id = ? AND P.id = ?~, undef,
        $cid, $pid);
    defined $status && ($is_jury || $status != $cats::problem_st_hidden)
        or return $p->not_found;
    my $already_hashed = CATS::Problem::Utils::ensure_problem_hash($pid, \$hash, 1);
    my $fname = "pr/problem_$hash.zip";
    my $fpath = downloads_path . $fname;
    unless($already_hashed && -f $fpath) {
        my ($zip) = $dbh->selectrow_array(qq~
            SELECT zip_archive FROM problems WHERE id = ?~, undef,
            $pid);
        CATS::BinaryFile::save($fpath, $zip);
    }
    $p->redirect(downloads_url . $fname);
}

sub problem_git_package {
    my ($p) = @_;
    my $pid = $p->{pid};
    my $sha = $p->{sha};
    $is_jury && $pid or return $p->redirect(url_f 'contests');
    my ($status) = $dbh->selectrow_array(qq~
        SELECT status FROM contest_problems
        WHERE contest_id = ? AND problem_id = ?~, undef,
        $cid, $pid) or return;
    undef $t;
    my ($fname, $tree_id) = CATS::Problem::Storage::get_repo_archive($pid, $sha);
    CATS::BinaryFile::load($fname, \my $content) or die "open '$fname' failed: $!";
    $p->print_file(
        content_type => 'application/zip',
        file_name => "problem_$tree_id.zip",
        len => stat($fname)->size,
        content => $content);
}

sub problem_select_testsets_frame {
    my ($p) = @_;
    init_template($p, 'problem_select_testsets.html.tt');
    $p->{pid} && $is_jury or return;
    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.id, P.title, CP.id AS cpid, CP.testsets, CP.points_testsets
        FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE P.id = ? AND CP.contest_id = ?~, undef,
        $p->{pid}, $cid) or return;

    my $testsets = $dbh->selectall_arrayref(q~
        SELECT * FROM testsets WHERE problem_id = ? ORDER BY name~, { Slice => {} },
        $problem->{id});

    my $param_to_list = sub {
        my ($field) = @_;
        my %sel;
        @sel{@{$p->{"sel_$field"}}} = undef;
        $problem->{$field} = join ',', map $_->{name}, grep exists $sel{$_->{id}}, @$testsets;
    };
    if ($p->{save}) {
        $dbh->do(q~
            UPDATE contest_problems SET testsets = ?, points_testsets = ?, max_points = NULL
            WHERE id = ?~, undef,
            map($param_to_list->($_), qw(testsets points_testsets)), $problem->{cpid});
        $dbh->commit;
        CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $problem->{cpid});
        return $p->redirect(url_f 'problems') if $p->{from_problems};
        msg(1141, $problem->{title});
    }

    my $list_to_selected = sub {
        my %sel;
        @sel{split ',', $problem->{$_[0]} || ''} = undef;
        $_->{"sel_$_[0]"} = exists $sel{$_->{name}} for @$testsets;
    };
    $list_to_selected->($_) for qw(testsets points_testsets);

    my $all_testsets = {};
    $all_testsets->{$_->{name}} = $_ for @$testsets;
    for (@$testsets) {
        $_->{count} = scalar keys %{CATS::Testset::parse_test_rank($all_testsets, $_->{name}, sub {})};
    }

    $t->param("problem_$_" => $problem->{$_}) for keys %$problem;
    $t->param(
        testsets => $testsets,
        href_action => url_f('problem_select_testsets', ($p->{from_problems} ? (from_problems => 1) : ())),
    );
    CATS::Problem::Utils::problem_submenu('problem_select_testsets', $p->{pid});
}

sub problem_limits_frame {
    my ($p) = @_;
    init_template($p, 'problem_limits.html.tt');
    $p->{pid} && $is_jury or return;

    my @fields = (@cats::limits_fields, 'job_split_strategy');
    my $original_limits_str = join ', ', 'NULL AS job_split_strategy', map "P.$_", @cats::limits_fields;
    my $overridden_limits_str = join ', ', map "L.$_ AS overridden_$_", @fields;

    my $problem = $dbh->selectrow_hashref(qq~
        SELECT P.id, P.title, CP.id AS cpid, CP.tags, CP.limits_id,
        $original_limits_str, $overridden_limits_str
        FROM problems P
        INNER JOIN contest_problems CP ON P.id = CP.problem_id
        LEFT JOIN limits L ON L.id = CP.limits_id
        WHERE P.id = ? AND CP.contest_id = ?~, undef,
        $p->{pid}, $cid) or return;
    CATS::Problem::Utils::round_time_limit($problem->{overridden_time_limit});

    $t->param(
        p => $problem,
        href_action => url_f('problem_limits', pid => $problem->{id}, cid => $cid,
            from_problems => $p->{from_problems})
    );

    CATS::Problem::Utils::problem_submenu('problem_limits', $p->{pid});

    if ($p->{override}) {
        my $new_limits = !defined $problem->{limits_id};

        my $limits = { map { $_ => $p->{$_} } grep $p->{$_}, @fields };
        my $filtered_limits = CATS::Request::filter_valid_limits($limits);

        return msg(1144) if !$new_limits && grep !exists $filtered_limits->{$_}, keys %$limits;

        $limits = {
            map { $_ => $limits->{$_} || $problem->{"overridden_$_"} || $problem->{$_} } @fields
        };

        $problem->{limits_id} = CATS::Request::set_limits($problem->{limits_id}, $limits);

        if ($new_limits) {
            $dbh->do(q~
                UPDATE contest_problems SET limits_id = ?
                WHERE id = ?~, undef,
            $problem->{limits_id}, $problem->{cpid});
        }

        for (@fields) {
            $problem->{"overridden_$_"} = $limits->{$_};
        }

        $dbh->commit;
        CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $problem->{cpid});

        msg($new_limits ? 1145 : 1146, $problem->{title});
        return $p->redirect(url_f 'problems') if $p->{from_problems} && !$new_limits;
    } elsif ($p->{clear_override}) {
        if ($problem->{limits_id}) {
            $dbh->do(q~
                UPDATE contest_problems SET limits_id = NULL
                WHERE id = ?~, undef,
            $problem->{cpid});
            CATS::Request::delete_limits($problem->{limits_id});
        }

        $dbh->commit;
        CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $problem->{cpid});

        delete $problem->{limits_id};
        for (@fields) {
            delete $problem->{"overridden_$_"};
        }

        msg(1147, $problem->{title});
        return $p->redirect(url_f 'problems') if $p->{from_problems};
    }
}

sub problem_test_data_frame {
    my ($p) = @_;
    init_template($p, 'problem_test_data.html.tt');
    $p->{pid} && $is_jury or return;

    if ($p->{clear_test_data}) {
        $dbh->do(q~
            UPDATE tests T SET T.in_file = NULL, T.in_file_size = NULL
            WHERE T.in_file_size IS NOT NULL AND T.problem_id = ?~, undef,
            $p->{pid});
        $dbh->do(q~
            UPDATE tests T SET T.out_file = NULL, T.out_file_size = NULL
            WHERE T.out_file_size IS NOT NULL AND T.problem_id = ?~, undef,
            $p->{pid});
        $dbh->commit;
    }
    if ($p->{clear_input_hashes}) {
        $dbh->do(q~
            UPDATE tests T SET T.in_file_hash = NULL WHERE T.problem_id = ?~, undef,
            $p->{pid});
        $dbh->commit;
    }

    my $problem = $dbh->selectrow_hashref(qq~
        SELECT P.id, P.title, CP.id AS cpid, CP.tags
        FROM problems P
            INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE P.id = ? AND CP.contest_id = ?~, undef,
        $p->{pid}, $cid) or return;

    my $tests = $dbh->selectall_arrayref(qq~
        SELECT PS.fname AS gen_name, T.rank, T.gen_group, T.param,
            SUBSTRING(T.in_file FROM 1 FOR $cats::test_file_cut + 1) AS input,
            T.in_file_size AS input_file_size,
            T.in_file_hash AS input_hash,
            SUBSTRING(T.out_file FROM 1 FOR $cats::test_file_cut + 1) AS answer,
            T.out_file_size AS answer_file_size
        FROM tests T
            LEFT JOIN problem_sources PS ON PS.id = generator_id
        WHERE T.problem_id = ? ORDER BY T.rank~, { Slice => {} },
        $p->{pid}) or return;

    for (@$tests) {
        $_->{input_cut} = length($_->{input} || '') > $cats::test_file_cut;
        $_->{answer_cut} = length($_->{answer} || '') > $cats::test_file_cut;
        $_->{generator_params} = CATS::Problem::Utils::gen_group_text($_);
        $_->{href_test_diff} = url_f('test_diff', pid => $p->{pid}, test => $_->{rank});
    };

    $t->param(p => $problem, tests => $tests);

    CATS::Problem::Utils::problem_submenu('problem_test_data', $p->{pid});
}

sub problem_select_tags_frame {
    my ($p) = @_;
    init_template($p, 'problem_select_tags.html.tt');
    $p->{pid} && $is_jury or return;

    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.id, P.title, CP.id AS cpid, CP.tags
        FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE P.id = ? AND CP.contest_id = ?~, undef,
        $p->{pid}, $cid) or return;

    if ($p->{save}) {
        my $tags = eval { CATS::Problem::Tags::parse_tag_condition($p->{tags}) };
        if (my $err = $@) {
            $err =~ s/\sat\s.+\d+\.$//;
            msg(1148, $err);
        }
        else {
            $dbh->do(q~
                UPDATE contest_problems SET tags = ? WHERE id = ?~, undef,
                $p->{tags}, $problem->{cpid});
            $dbh->commit;
            return $p->redirect(url_f 'problems') if $p->{from_problems};
            msg(1142, $problem->{title});
        }
        $problem->{tags} = $p->{tags};
    }

    $t->param(
        problem => $problem,
        href_action => url_f('problem_select_tags',
            from_problems => $p->{from_problems}, pid => $p->{pid}),
        available_tags => CATS::Problem::Text::get_tags($p->{pid}),
    );
    CATS::Problem::Utils::problem_submenu('problem_select_tags', $p->{pid});
}

sub problem_des_frame {
    my ($p) = @_;

    init_template($p, 'problem_des.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'problem_des', array_name => 'problem_sources');

    $p->{pid} && $is_jury or return;

    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.id, P.title, P.commit_sha, CP.id AS cpid, CP.tags
        FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE P.id = ? AND CP.contest_id = ?~, undef,
        $p->{pid}, $cid) or return;
    $problem->{commit_sha} = eval { CATS::Problem::Storage::get_latest_master_sha($p->{pid}); } || 'error';

    my $des = $p->{save} ?
        CATS::Problem::Save::set_contest_problem_des($problem->{cpid}, $p->{allow}, 'id') :
        CATS::Problem::Save::get_all_des($problem->{cpid});

    $lv->define_columns(url_f('problem_des', pid => $p->{pid}), 0, 0, [
        { caption => res_str(642), order_by => 'stype', width => '10%' },
        { caption => res_str(601), order_by => 'name', width => '20%' },
        { caption => res_str(674), order_by => 'fname', width => '20%' },
        { caption => res_str(619), order_by => 'code', width => '20%' },
        { caption => res_str(641), order_by => 'description', width => '20%' },
    ]);
    $lv->define_db_searches([qw(stype name fname D.id code description)]);

    my $c = $dbh->prepare(q~
        SELECT PS.stype, PS.name, PS.fname, D.id, D.code, D.description
        FROM problem_sources PS INNER JOIN default_de D ON PS.de_id = D.id
        WHERE PS.problem_id = ? ~ . $lv->maybe_where_cond . $lv->order_by);
    $c->execute($p->{pid}, $lv->where_params);

    my $fetch_record = sub {
        my $c = $_[0]->fetchrow_hashref or return ();
        return (
            %$c,
            type_name => $cats::source_module_names{$c->{stype}},
            href_edit => url_f('problem_history_edit',
                pid => $p->{pid}, file => $c->{fname}, hb => $problem->{commit_sha}),
        );
    };

    $lv->attach(url_f('problem_des', pid => $p->{pid}), $fetch_record, $c);
    $c->finish;

    $t->param(
        problem_title => $problem->{title},
        title_suffix => $problem->{title},
        problem => $problem,
        des => $des,
        de_matrix => CATS::DeGrid::matrix($des, 3),
    );
    CATS::Problem::Utils::problem_submenu('problem_des', $p->{pid});
}

sub problem_link_frame {
    my ($p) = @_;
    $p->{pid} && $is_jury or return;

    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.id, P.title, CP.id AS cpid, P.contest_id
        FROM problems P
        INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE P.id = ? AND CP.contest_id = ?~, undef,
        $p->{pid}, $cid) or return;

    init_template($p, 'problem_link.html.tt');
    $p->{listview} = my $lv = CATS::ListView->new(
        web => $p, name => 'problem_link', array_name => 'contests');

    CATS::Problem::Utils::problem_submenu('problem_link', $p->{pid});
    my $href_action = url_f('problem_link', pid => $p->{pid});
    $t->param(
        problem_title => $problem->{title},
        title_suffix => $problem->{title},
        problem => $problem,
        href_action => $href_action,
    );

    if ($problem->{contest_id} != $cid) {
        if ($p->{move_from} && CATS::Problem::Save::move_problem($p->{pid}, undef, $cid)) {
            $problem->{contest_id} = $cid;
        }
    }
    elsif ($p->{contest_id}) {
        if ($p->{move_to} && CATS::Problem::Save::move_problem($p->{pid}, $p->{code}, $p->{contest_id})) {
            $problem->{contest_id} = $p->{contest_id};
        }
        elsif ($p->{link_to}) {
            CATS::Problem::Save::link_problem($problem->{id}, $p->{code}, $p->{contest_id});
        }
    }

    $problem->{is_original} = $problem->{contest_id} == $cid;
    $t->param(href_original_contest =>
        url_function('problems', cid => $problem->{contest_id}, sid => $sid));
    if (!$problem->{is_original}) {
        $problem->{original_contest_title} = $dbh->selectrow_array(q~
            SELECT title FROM contests WHERE id = ?~, undef,
            $problem->{contest_id});
        return;
    }

    $lv->define_columns($href_action, 2, 1, [
        { caption => res_str(601), order_by => 'ctype DESC, title', width => '50%' },
        { caption => res_str(663), order_by => 'ctype DESC, problems_count', width => '10%' },
        { caption => res_str(600), order_by => 'ctype DESC, start_date', width => '15%' },
        { caption => res_str(631), order_by => 'ctype DESC, finish_date', width => '15%' },
    ]);

    $p->{extra_fields} = [
    q~(
        SELECT COUNT(*) FROM contest_problems CP WHERE CP.contest_id = C.id) AS problems_count~,
    qq~(
        SELECT 1 FROM contest_problems CP
        WHERE CP.contest_id = C.id AND CP.problem_id = $problem->{id}) AS has_this_problem~,
    ];
    $p->{filter} = $is_root ? '' : ' AND CA.is_jury = 1';

    $lv->attach(url_f('problem_link', pid => $p->{pid}),
        CATS::Contest::Utils::authenticated_contests_view($p));
}

1;
