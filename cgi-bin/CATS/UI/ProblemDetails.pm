package CATS::UI::ProblemDetails;

use strict;
use warnings;

use File::stat;
use List::Util qw(sum);

use CATS::BinaryFile;
use CATS::Constants;
use CATS::DB qw(:DEFAULT $db);
use CATS::DeGrid;
use CATS::Form;
use CATS::Globals qw($cid $contest $is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(downloads_path downloads_url init_template url_f url_f_cid);
use CATS::Problem::Save;
use CATS::Problem::Storage;
use CATS::Problem::Tags;
use CATS::Problem::Text;
use CATS::Problem::Utils;
use CATS::Settings;
use CATS::StaticPages;
use CATS::Testset;
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
            P.id, P.title, P.lang, P.contest_id, P.author, P.last_modified_by, P.upload_date,
            P.run_method, P.save_input_prefix, P.save_answer_prefix, P.save_output_prefix,
            P.time_limit, P.memory_limit, P.write_limit, P.repo_path, P.commit_sha,
            OCTET_LENGTH(P.zip_archive) AS package_size,
            L.time_limit AS overridden_time_limit,
            L.memory_limit AS overridden_memory_limit,
            L.write_limit as overridden_write_limit,
            C.title AS contest_name, A.team_name,
            CP.id AS cpid, CP.testsets, CP.points_testsets, CP.tags, CP.code,
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
    $pr->{upload_date} = $db->format_date($pr->{upload_date});

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
            href_all => url_f('console',
                search => $search, %p, , show_contests => 0, show_messages => 0),
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
        href_original_contest => url_f_cid('problems', cid => $pr->{contest_id}),
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
    my $all_testsets = {};
    $all_testsets->{$_->{name}} = $_ for @$testsets;

    my @ts_fields = qw(testsets points_testsets);
    my $testset_text_error;
    if ($p->{save_text}) {
        for my $f (@ts_fields) {
            my $t = $p->{$f . '_text'};
            CATS::Testset::parse_test_rank(
                $all_testsets, $t, sub { msg(1149, $f, $_[0]); $testset_text_error = 1; });
            $problem->{$f} = $t;
        }
    }

    my $param_to_list = sub {
        my ($field) = @_;
        my %sel;
        @sel{@{$p->{"sel_$field"}}} = undef;
        $problem->{$field} = join ',', map $_->{name}, grep exists $sel{$_->{id}}, @$testsets;
    };
    if ($p->{save} || !$testset_text_error && $p->{save_text}) {
        my @testset_text = $p->{save} ?
            map($param_to_list->($_), @ts_fields) :
            map($p->{$_ . '_text'}, @ts_fields);
        $dbh->do(q~
            UPDATE contest_problems SET testsets = ?, points_testsets = ?, max_points = NULL
            WHERE id = ?~, undef,
            @testset_text, $problem->{cpid});
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
    $list_to_selected->($_) for @ts_fields;

    for (@$testsets) {
        $_->{count} = scalar keys %{CATS::Testset::parse_test_rank($all_testsets, $_->{name}, sub {})};
        $_->{href_tests} = url_f(problem_test_data => pid => $p->{pid}, search => "rank=$_->{name}");
    }

    $t->param("problem_$_" => $problem->{$_}) for keys %$problem;
    $t->param(
        testsets => $testsets,
        href_action => url_f('problem_select_testsets', ($p->{from_problems} ? (from_problems => 1) : ())),
    );
    CATS::Problem::Utils::problem_submenu('problem_select_testsets', $p->{pid});
}

my $test_data_sql = qq~
    SELECT T.rank, T.gen_group, T.param, T.descr,
        SUBSTRING(T.in_file FROM 1 FOR $cats::test_file_cut + 1) AS input,
        COALESCE(PSL1.fname, PSLE1.fname) AS gen_name,
        COALESCE(PSL2.fname, PSLE2.fname) AS val_name,
        COALESCE(PSL3.fname, PSLE3.fname) AS sol_name,
        COALESCE(T.in_file_size, OCTET_LENGTH(T.in_file)) AS input_size,
        T.in_file_hash AS input_hash,
        T.input_validator_id,
        T.input_validator_param,
        SUBSTRING(T.out_file FROM 1 FOR $cats::test_file_cut + 1) AS answer,
        COALESCE(T.out_file_size, OCTET_LENGTH(T.out_file)) AS answer_size
    FROM tests T

        LEFT JOIN problem_sources PS1 ON PS1.id = T.generator_id
        LEFT JOIN problem_sources_local PSL1 ON PSL1.id = PS1.id
        LEFT JOIN problem_sources_imported PSI1 ON PSI1.id = PS1.id
        LEFT JOIN problem_sources_local PSLE1 ON PSLE1.guid = PSI1.guid

        LEFT JOIN problem_sources PS2 ON PS2.id = T.input_validator_id
        LEFT JOIN problem_sources_local PSL2 ON PSL2.id = PS2.id
        LEFT JOIN problem_sources_imported PSI2 ON PSI2.id = PS2.id
        LEFT JOIN problem_sources_local PSLE2 ON PSLE2.guid = PSI2.guid

        LEFT JOIN problem_sources PS3 ON PS3.id = T.std_solution_id
        LEFT JOIN problem_sources_local PSL3 ON PSL3.id = PS3.id
        LEFT JOIN problem_sources_imported PSI3 ON PSI3.id = PS3.id
        LEFT JOIN problem_sources_local PSLE3 ON PSLE3.guid = PSI3.guid

    WHERE T.problem_id = ? ~;

sub _to_exe {
    my ($src) = @_;
    $src =~ s/^([^\s\.]+\.)([a-z]+)/$1exe/;
    $src;
}

sub _test_gen_line {
    my ($test, $problem, $len) = @_;
    my $fmt = "\%0${len}d";
    my @result;
    if (!$test->{input}) {
        push @result, sprintf("%s %s >$fmt.in",
            _to_exe($test->{gen_name}), $test->{param}, $test->{rank});
    }
    if ($problem->{input_file} eq '*STDIN') {
        push @result, sprintf("%s <$fmt.in >$fmt.out",
            _to_exe($test->{sol_name}), $test->{rank}, $test->{rank});
    }
    else {
        push @result, sprintf("copy $fmt.in %s", $test->{rank}, $problem->{input_file});
        push @result, _to_exe($test->{sol_name});
        push @result, sprintf("ren %s $fmt.out", $problem->{output_file}, $test->{rank});
    }
    @result;
}

sub problem_test_gen_script_frame {
    my ($p) = @_;
    $p->{pid} && $is_jury or return;
    my $problem = $dbh->selectrow_hashref(qq~
        SELECT P.id, P.title, P.input_file, P.output_file, CP.id AS cpid, CP.tags
        FROM problems P
            INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE P.id = ? AND CP.contest_id = ?~, undef,
        $p->{pid}, $cid) or return;
    my $tests = $dbh->selectall_arrayref(
        $test_data_sql . ' ORDER BY T.rank', { Slice => {} },
        $p->{pid});
    my $len = @$tests > 99 ? 3 : 2;
    my $script = join '', map "$_\n", map _test_gen_line($_, $problem, $len), @$tests;
    $p->print_file(
        content_type => 'text/plain', charset => 'UTF-8',
        inline => 1, file_name => "gen_tests_$p->{pid}.cmd",
        content => Encode::encode_utf8($script));
}

sub problem_test_data_frame {
    my ($p) = @_;
    init_template($p, 'problem_test_data.html.tt');
    $p->{pid} && $is_jury or return;

    my $problem = $dbh->selectrow_hashref(qq~
        SELECT P.id, P.title, CP.id AS cpid, CP.tags
        FROM problems P
            INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE P.id = ? AND CP.contest_id = ?~, undef,
        $p->{pid}, $cid) or return;

    if ($p->{clear_test_data}) {
        CATS::Problem::Utils::clear_test_data($p->{pid});
        $dbh->commit;
    }
    if ($p->{clear_input_hashes}) {
        $dbh->do(q~
            UPDATE tests T SET in_file_hash = NULL WHERE T.problem_id = ?~, undef,
            $p->{pid});
        $dbh->commit;
    }

    my $lv = CATS::ListView->new(
        web => $p, name => 'problem_test_data',
        array_name => 'tests', url => url_f('problem_test_data', pid => $p->{pid}));

    $lv->default_sort(0)->define_columns([
        { caption => 'test', order_by => 'T.rank', },
        { caption => 'input', order_by => 'input' },
        { caption => 'input_size', order_by => 'input_size', col => 'Is' },
        { caption => 'answer', order_by => 'answer', width => '5%' },
        { caption => 'answer_size', order_by => 'answer_size', col => 'As' },
        { caption => 'generator_params', order_by => 'gen_name' },
        { caption => 'validator', order_by => 'val_name', col => 'Vn' },
        { caption => 'input_hash', order_by => 'input_hash', col => 'Ih' },
        { caption => 'descr', order_by => 'descr', col => 'De' },
    ]);
    $lv->define_db_searches([ qw(
        rank gen_group param input_hash input_validator_param
        in_file in_file_size out_file out_file_size descr
    ) ]);
    $lv->define_db_searches({
        gen_name => 'COALESCE(PSL1.fname, PSLE1.fname)',
        val_name => 'COALESCE(PSL2.fname, PSLE2.fname)',
    });

    my $all_testsets = $dbh->selectall_hashref(q~
        SELECT * FROM testsets WHERE problem_id = ? ORDER BY name~, 'name', { Slice => {} },
        $problem->{id});
    $lv->define_enums({ rank => { map { $_ => $_ } keys %$all_testsets } });
    $lv->define_transforms({ rank => sub {
            [ keys %{CATS::Testset::parse_test_rank(
                $all_testsets, $_[0], sub { msg(1149, 'rank', $_[0]); })} ];
    } });

    my $sth = $dbh->prepare($test_data_sql . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($p->{pid}, $lv->where_params);

    my ($parsed, $sha) = CATS::Problem::Storage->new->parse_problem($cid, $p->{pid});

    my $total = {};

    my $set_file_name = sub {
        my ($row, $field) = @_;
        $row->{$field} = $parsed->{tests}->{$row->{rank}}->{$field} and
            url_f('problem_history_edit', file => $row->{$field}, pid => $p->{pid}, hb => $sha);
    };

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        $row->{input_cut} = length($row->{input} || '') > $cats::test_file_cut;
        $row->{answer_cut} = length($row->{answer} || '') > $cats::test_file_cut;
        $row->{generator_params} = CATS::Problem::Utils::gen_group_text($row);
        $row->{href_test_diff} = url_f('test_diff', pid => $p->{pid}, test => $row->{rank});
        $row->{href_edit_in} = $set_file_name->($row, 'in_file_name');
        $row->{href_edit_out} = $set_file_name->($row, 'out_file_name');
        $total->{input_size} += $row->{input_size} // 0;
        $total->{answer_size} += $row->{answer_size} // 0;
        %$row;
    };

    $lv->attach($fetch_record, $sth);
    $sth->finish;

    $t->param(
        p => $problem, problem_title => $problem->{title}, total => $total,
        href_test_gen_script => url_f('problem_test_gen_script', pid => $p->{pid}),
    );

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
        problem_title => $problem->{title},
        href_action => url_f('problem_select_tags',
            from_problems => $p->{from_problems}, pid => $p->{pid}),
        available_tags => CATS::Problem::Text::get_tags($p->{pid}),
    );
    CATS::Problem::Utils::problem_submenu('problem_select_tags', $p->{pid});
}

sub problem_des_frame {
    my ($p) = @_;

    init_template($p, 'problem_des');
    my $lv = CATS::ListView->new(
        web => $p, name => 'problem_des', array_name => 'problem_sources',
        url => url_f('problem_des', pid => $p->{pid}));

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

    $lv->default_sort(0)->define_columns([
        { caption => res_str(642), order_by => 'stype', width => '10%' },
        { caption => res_str(601), order_by => 'name', width => '20%' },
        { caption => res_str(674), order_by => 'fname', width => '20%' },
        { caption => res_str(619), order_by => 'code', width => '20%' },
        { caption => res_str(641), order_by => 'description', width => '20%' },
    ]);
    $lv->define_db_searches([qw(stype name fname D.id code description)]);
    $lv->default_searches([ qw(name code description) ]);

    my $sth = $dbh->prepare(q~
        SELECT
            COALESCE(PSL.stype, PSLE.stype) AS stype,
            COALESCE(PSL.name, PSLE.name) AS name,
            COALESCE(PSL.fname, PSLE.fname) AS fname,
            D.id, D.code, D.description
        FROM problem_sources PS
        LEFT JOIN problem_sources_local PSL ON PSL.id = PS.id
        LEFT JOIN problem_sources_imported PSI ON PSI.id = PS.id
        LEFT JOIN problem_sources_local PSLE ON PSLE.guid = PSI.guid
        INNER JOIN default_de D ON COALESCE(PSL.de_id, PSLE.de_id) = D.id
        WHERE PS.problem_id = ? ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($p->{pid}, $lv->where_params);

    my $fetch_record = sub {
        my $c = $_[0]->fetchrow_hashref or return ();
        return (
            %$c,
            type_name => $cats::source_module_names{$c->{stype}},
            href_edit => url_f('problem_history_edit',
                pid => $p->{pid}, file => $c->{fname}, hb => $problem->{commit_sha}),
        );
    };

    $lv->attach($fetch_record, $sth);
    $sth->finish;

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

    init_template($p, 'problem_link');
    my $href_action = url_f('problem_link', pid => $p->{pid});
    $p->{listview} = my $lv = CATS::ListView->new(
        web => $p, name => 'problem_link', array_name => 'contests', url => $href_action);

    CATS::Problem::Utils::problem_submenu('problem_link', $p->{pid});
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
    $t->param(href_original_contest => url_f_cid('problems', cid => $problem->{contest_id}));
    if (!$problem->{is_original}) {
        $problem->{original_contest_title} = $dbh->selectrow_array(q~
            SELECT title FROM contests WHERE id = ?~, undef,
            $problem->{contest_id});
        return;
    }

    $lv->default_sort(2, 1)->define_columns([
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

    $lv->attach(CATS::Contest::Utils::authenticated_contests_view($p));
}

1;
