package CATS::UI::RunDetails;

use strict;
use warnings;

use Algorithm::Diff;
use List::Util qw(max);
use JSON::XS;

use CATS::BinaryFile;
use CATS::Constants;
use CATS::DB;
use CATS::DevEnv;
use CATS::Globals qw($is_jury $is_root $sid $cid $t $uid);
use CATS::IP;
use CATS::JudgeDB;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template downloads_path downloads_url url_f);
use CATS::Problem::Utils;
use CATS::RankTable;
use CATS::Request;
use CATS::ReqDetails qw(
    get_contest_info
    get_contest_tests
    get_log_dump
    get_req_details
    get_sources_info
    get_test_data
    sources_info_param
    source_links);
use CATS::Settings qw($settings);
use CATS::Testset;
use CATS::Utils;
use CATS::Verdicts;
use CATS::Web qw(param encoding_param url_param headers upload_source content_type);

sub get_run_info {
    my ($contest, $req) = @_;
    my $points = $contest->{points};

    my $last_test = 0;
    my $total_points = 0;
    my $all_testsets = CATS::Testset::get_all_testsets($dbh, $req->{problem_id});
    my %testset = CATS::Testset::get_testset($dbh, $req->{req_id});
    $contest->{show_points} ||= 0 < grep $_, values %testset;
    my (%run_details, %used_testsets, %accepted_tests, %accepted_deps);

    my $comment_enc = encoding_param('comment_enc');

    my @resources = qw(time_used memory_used disk_used);
    my $rd_fields = join ', ', (
         qw(test_rank result points),
         ($contest->{show_test_resources} ? @resources : ()),
         ($contest->{show_checker_comment} || $req->{partial_checker} ? qw(checker_comment) : ()),
    );

    for my $row (get_req_details($contest, $req, $rd_fields, \%accepted_tests)) {
        $_ and $_ = sprintf('%.3g', $_) for $row->{time_used};
        if ($contest->{show_checker_comment}) {
            my $d = $row->{checker_comment} || '';
            # Comment may be non-well-formed utf8
            $row->{checker_comment} = Encode::decode($comment_enc, $d, Encode::FB_QUIET);
            $row->{checker_comment} .= '...' if $d ne '';
        }

        $last_test = $row->{test_rank};
        my $p = $row->{is_accepted} ? $row->{points} || $points->[$row->{test_rank} - 1] || 0 : 0;
        if (my $ts = $row->{ts} = $testset{$last_test}) {
            $used_testsets{$ts->{name}} = $ts;
            $ts->{accepted_count} //= 0;
            push @{$ts->{list} ||= []}, $last_test;
            if (CATS::RankTable::dependencies_accepted($all_testsets, $ts, \%accepted_tests, \%accepted_deps)) {
                $ts->{accepted_count} += $row->{is_accepted};
                if (defined $ts->{points}) {
                    $total_points += $ts->{earned_points} = $ts->{points}
                        if $ts->{accepted_count} == $ts->{test_count};
                }
                else {
                    $total_points += $p;
                    $ts->{earned_points} += $p;
                }
            }
            else {
                $p = 'X';
            }
            if ($ts->{hide_details} && $contest->{hide_testset_details}) {
                $row->{is_hidden} = 1;
            }
            if (defined $ts->{points} || $ts->{hide_details} && $contest->{hide_testset_details}) {
                $p = '';
            }
            $p .= " => $ts->{name}";
        }
        elsif ($row->{is_accepted} && $req->{partial_checker}) {
            $total_points += $p = CATS::RankTable::get_partial_points($row, $p);
        }
        else {
            $total_points += $p;
        }
        $run_details{$last_test} = {
            %$row, points => $p,
            short_state => $row->{is_hidden} ? '' : $CATS::Verdicts::state_to_name->{$row->{result}},
        };
    }

    # Output 'not processed' for tests we do not plan to run, but must still display.
    if ($contest->{show_all_tests} && !$contest->{run_all_tests}) {
        $last_test = @$points;
    }
    if ($contest->{hide_testset_details}) {
        for (values %used_testsets) {
            $_->{accepted_count} = '?'
                if $_->{hide_details} && $_->{accepted_count} != $_->{test_count};
        }
    }

    my $run_row = sub {
        my ($rank) = @_;
        return $run_details{$rank} if exists $run_details{$rank};
        return () unless $contest->{show_all_tests};
        my %r = (test_rank => $rank, ts => $testset{$rank});
        $r{short_state} = exists $testset{$rank} ? 'NP' : 'NT';
        return \%r;
    };

    my $visualizers = $dbh->selectall_arrayref(q~
        SELECT PS.id, PS.name
        FROM problem_sources PS
        INNER JOIN problems P ON PS.problem_id = P.id
        INNER JOIN reqs R ON R.problem_id = P.id
        WHERE R.id = ? AND PS.stype = ?~, { Slice => {} },
        $req->{req_id}, $cats::visualizer);

    my %outputs = map { $_->{test_rank} => $_->{output} } @{$dbh->selectall_arrayref(qq~
        SELECT SUBSTRING(SO.output FROM 1 FOR $cats::test_file_cut + 1) as output, SO.test_rank
        FROM solution_output SO WHERE SO.req_id = ? AND SO.test_rank <= ?~, { Slice => {} },
        $req->{req_id}, $last_test)};

    my $maximums = { map { $_ => 0 } @resources };
    my $add_testdata = sub {
        my ($row) = @_ or return ();
        $contest->{show_test_data} or return $row;
        my $t = $contest->{tests}->[$row->{test_rank} - 1] or return $row;
        $t->{param} //= '';
        $row->{input_gen_params} = CATS::Problem::Utils::gen_group_text($t);
        $row->{input_data} =
            defined $t->{input} ? $t->{input} : $row->{input_gen_params};
        $row->{input_data_cut} = length($t->{input} || '') > $cats::test_file_cut;
        $row->{answer_data} = $t->{answer};
        $row->{answer_data_cut} = length($t->{answer} || '') > $cats::test_file_cut;
        $row->{visualize_test_hrefs} =
            defined $t->{input} ? [ map +{
                href => url_f('visualize_test', rid => $req->{req_id}, test_rank => $row->{test_rank}, vid => $_->{id}),
                name => $_->{name}
            }, @$visualizers ] : [];
        $maximums->{$_} = max($maximums->{$_}, $row->{$_} // 0) for @resources;
        $row->{output_data} = $outputs{$row->{test_rank}};
        $row->{output_data_cut} = length($row->{output_data} || '') > $cats::test_file_cut;
        $row->{view_test_details_href} = url_f('view_test_details', rid => $req->{req_id}, test_rank => $row->{test_rank});
        $row;
    };
    if (
        $contest->{show_points} && $contest->{points} &&
        # Do not cache incomplete points to avoid messing up RankTable cache.
        $req->{state} > $cats::request_processed &&
        (!defined $req->{points} || $req->{points} != $total_points)
    ) {
        $req->{points} = $total_points;
        eval {
            $req->{needs_commit} = $dbh->do(q~
                UPDATE reqs SET points = ? WHERE id = ? AND points IS DISTINCT FROM ?~, undef,
                $req->{points}, $req->{req_id}, $req->{points});
            1;
        } or CATS::DB::catch_deadlock_error("get_run_info $req->{req_id}");
    }

    return {
        %$contest,
        id => $req->{req_id},
        total_points => $total_points,
        run_details => [ map $add_testdata->($run_row->($_)), 1..$last_test ],
        maximums => $maximums,
        testsets => [ sort { $a->{list}[0] <=> $b->{list}[0] } values %used_testsets ],
        accepted_deps => \%accepted_deps,
        has_depends_on => 0 < grep($_->{depends_on}, values %used_testsets),
        has_visualizer => @$visualizers > 0,
        has_output => $req->{save_output_prefix},
    };
}

sub run_details_frame {
    my ($p) = @_;
    init_template('run_details.html.tt');

    my $sources_info = get_sources_info(request_id => $p->{rid}, partial_checker => 1) or return;
    my @runs;
    my $contest_cache = {};

    my $needs_commit;
    for (@$sources_info) {
        source_links($_);
        if ($_->{state} == $cats::st_compilation_error) {
            push @runs, { get_log_dump($_->{req_id}, 1) };
            next;
        }
        my $c = get_contest_tests(get_contest_info($_, $contest_cache), $_->{problem_id});
        push @runs, get_run_info($c, $_);
        $needs_commit ||= $_->{needs_commit};
    }
    $dbh->commit if $needs_commit;
    sources_info_param($sources_info);
    $t->param(runs => \@runs,
        display_input => $settings->{display_input},
        display_answer => $settings->{display_input},
        display_output => $settings->{display_input}, #TODO: Add this params to settings
    );
}

sub save_visualizer {
    my ($data, $lfname, $pid, $hash) = @_;

    CATS::Problem::Utils::ensure_problem_hash($pid, \$hash, 1);

    my $fname = "vis/${hash}_$lfname";
    my $fpath = downloads_path . $fname;
    -f $fpath or CATS::BinaryFile::save($fpath, $data);
    return downloads_url . $fname;
}

sub visualize_test_frame {
    my ($p) = @_;
    init_template('visualize_test.html.tt');

    $uid or return;
    my $rid = $p->{rid} or return;
    my $vid = $p->{vid} or return;
    my $test_rank = $p->{test_rank} or return;

    my $sources_info = get_sources_info(
        request_id => $rid, extra_params => [ test_rank => $test_rank, vid => $p->{vid} ]);
    source_links($sources_info);
    sources_info_param([ $sources_info ]);

    my $ci = get_contest_info($sources_info, {});
    $ci->{show_test_data} or return;

    my @tests = get_req_details($ci, $sources_info, 'test_rank, result', {});
    grep $_->{test_rank} == $test_rank, @tests or return;

    my $visualizer = $dbh->selectrow_hashref(q~
        SELECT PS.name, PS.src, PS.fname, P.id AS problem_id, P.hash
        FROM problem_sources PS
        INNER JOIN problems P ON PS.problem_id = P.id
        INNER JOIN reqs R ON R.problem_id = P.id
        WHERE R.id = ? AND PS.id = ? AND PS.stype = ?~, { Slice => {} },
        $rid, $vid, $cats::visualizer) or return;

    my @imports_js = (@{$dbh->selectall_arrayref(q~
        SELECT PS.src, PS.fname, PS.problem_id, P.hash
        FROM problem_sources_import PSI
        INNER JOIN problem_sources PS ON PS.guid = PSI.guid
        INNER JOIN problems P ON P.id = PS.problem_id
        WHERE PSI.problem_id = ? AND PS.stype = ?~, { Slice => {} },
        $visualizer->{problem_id}, $cats::visualizer_module)}, $visualizer);

    my $test_data = get_test_data($p) or return;

    @{$test_data}{qw(output output_size)} = $dbh->selectrow_array(q~
        SELECT SO.output, SO.output_size
        FROM solution_output SO
        WHERE SO.req_id = ? AND SO.test_rank = ?~, undef,
        $rid, $test_rank);

    my $vhref = sub { url_f('visualize_test', rid => $rid, test_rank => $_[0], vid => $vid) };

    $t->param(
        vis_scripts => [
            map save_visualizer($_->{src}, $_->{fname}, $_->{problem_id}, $_->{hash}), @imports_js
        ],
        test_data_json => JSON::XS->new->utf8->indent(2)->canonical->encode($test_data),
        visualizer => $visualizer,
        href_prev_pages => $test_rank > $tests[0]->{test_rank} ? $vhref->($test_rank - 1) : undef,
        href_next_pages => $test_rank < $tests[-1]->{test_rank} ? $vhref->($test_rank + 1) : undef,
        test_ranks => [
            map +{
                page_number => $_->{test_rank},
                href_page => $vhref->($_->{test_rank}),
                current_page => $_->{test_rank} == $test_rank,
                short_verdict => $CATS::Verdicts::state_to_name->{$_->{result}},
            }, @tests
        ],
    );
}

sub view_source_frame {
    my ($p) = @_;
    init_template('view_source.html.tt');
    $p->{rid} or return;
    my $sources_info = get_sources_info(request_id => $p->{rid}, get_source => 1, encode_source => 1);
    $sources_info or return;

    if ($sources_info->{is_jury} && $p->{replace}) {
        my $u;
        if (param('replace_file')) {
            $u->{src} = upload_source('replace_file') or die;
            $u->{hash} = CATS::Utils::source_hash($u->{src});
        }
        my $de_bitmap;
        if ($p->{de_id} && $p->{de_id} != $sources_info->{de_id}) {
            $u->{de_id} = $p->{de_id};
            $de_bitmap = [ CATS::DevEnv->new(CATS::JudgeDB::get_DEs())->bitmap_by_ids($p->{de_id}) ];
        }
        if ($u) {
            CATS::Request::update_source($sources_info->{req_id}, $u, $de_bitmap);
            $dbh->commit;
            $sources_info = get_sources_info(request_id => $p->{rid}, get_source => 1, encode_source => 1);
        }
    }
    source_links($sources_info);
    sources_info_param([ $sources_info ]);
    @{$sources_info->{elements}} <= 1 or return msg(1155);

    if ($sources_info->{file_name} =~ m/\.zip$/) {
        $sources_info->{src} = sprintf 'ZIP, %d bytes', length ($sources_info->{src});
    }
    if (my $r = $sources_info->{err_regexp}) {
        CATS::Utils::sanitize_file_name(my $sf = $sources_info->{file_name});
        $sf =~ s/([^a-zA-Z0-9_])/\\$1/g;
        for (split ' ', $r) {
            s/~FILE~/$sf/;
            s/~LINE~/(\\d+)/;
            s/~POS~/\\d+/;
            push @{$sources_info->{err_regexp_js}}, "/$_/";
        }
    }
    $sources_info->{syntax} = $p->{syntax} if $p->{syntax};
    $sources_info->{src_lines} = [ map {}, split("\n", $sources_info->{src}) ];
    $sources_info->{compiler_output} = { get_log_dump($sources_info->{req_id}, 1) }
        if $sources_info->{state} == $cats::st_compilation_error;

    if ($sources_info->{is_jury}) {
        my $de_list = CATS::DevEnv->new(CATS::JudgeDB::get_DEs({ active_only => 1 }));
        if ($p->{de_id}) {
            $sources_info->{de_id} = $p->{de_id};
            $sources_info->{de_name} = $de_list->by_id($p->{de_id})->{description};
        }
        $t->param(de_list => [
            map {
                de_id => $_->{id},
                de_name => $_->{description},
                selected => $_->{id} == $sources_info->{de_id},
            }, @{$de_list->des}
        ]);
    }
}

sub download_source_frame {
    my $rid = url_param('rid') or return;
    my $si = get_sources_info(request_id => $rid, get_source => 1, encode_source => 1);

    unless ($si) {
        init_template('view_source.html.tt');
        return;
    }

    $si->{file_name} =~ m/\.([^.]+)$/;
    my $ext = $1 || 'unknown';
    content_type($ext eq 'zip' ? 'application/zip' : 'text/plain', 'UTF-8');
    headers('Content-Disposition' => "inline;filename=$si->{req_id}.$ext");
    CATS::Web::print(Encode::encode_utf8($si->{src}));
}

sub view_test_details_frame {
    my ($p) = @_;
    init_template('view_test_details.html.tt');

    $p->{rid} or return;
    $p->{test_rank} //= 1;

    my $sources_info = get_sources_info(
        request_id => $p->{rid}, extra_params => [ test_rank => $p->{test_rank} ]) or return;

    my $ci = get_contest_info($sources_info, {});
    $ci->{show_test_data} or return;

    my $output_data;
    if ($is_jury && $p->{delete_request_outputs}) {
        $dbh->do(q~
            DELETE FROM solution_output SO WHERE SO.req_id = ?~, undef,
            $p->{rid});
        $dbh->commit;
    } elsif($is_jury && $p->{delete_test_output}) {
        $dbh->do(q~
            DELETE FROM solution_output SO WHERE SO.req_id = ? AND SO.test_rank = ?~, undef,
            $p->{rid}, $p->{test_rank});
        $dbh->commit;
    } else {
        $output_data = $dbh->selectrow_hashref(q~
            SELECT SO.output, SO.output_size FROM solution_output SO
            WHERE SO.req_id = ? AND SO.test_rank = ?~, { Slice => {} },
            $p->{rid}, $p->{test_rank});
    }

    my $save_prefix_lengths = $dbh->selectrow_hashref(q~
        SELECT
            p.save_input_prefix as input_prefix,
            p.save_answer_prefix as answer_prefix,
            p.save_output_prefix as output_prefix
        FROM problems P
            INNER JOIN reqs R ON R.problem_id = P.id
        WHERE R.id = ?~, { Slice => {} },
        $p->{rid});

    my $test_data = get_test_data($p);

    my $tdhref = sub { url_f('view_test_details', rid => $p->{rid}, test_rank => $_[0]) };

    my @tests = get_req_details($ci, $sources_info, 'test_rank, result', {});
    grep $_->{test_rank} == $p->{test_rank}, @tests or return;

    source_links($sources_info);
    sources_info_param([ $sources_info ]);
    $t->param(
        output_data => $output_data,
        test_data => $test_data,
        save_prefix_lengths => $save_prefix_lengths,
        href_prev_pages => $p->{test_rank} > $tests[0]->{test_rank} ? $tdhref->($p->{test_rank} - 1) : undef,
        href_next_pages => $p->{test_rank} < $tests[-1]->{test_rank} ? $tdhref->($p->{test_rank} + 1) : undef,
        test_ranks => [
            map +{
                page_number => $_->{test_rank},
                href_page => $tdhref->($_->{test_rank}),
                current_page => $_->{test_rank} == $p->{test_rank},
                short_verdict => $CATS::Verdicts::state_to_name->{$_->{result}},
            }, @tests
        ],
    );
}

sub maybe_reinstall {
    my ($p, $si) = @_;
    $p->{reinstall} && $si->{can_reinstall} or return;
    # Advance problem modification date to mark judges' cache stale.
    $dbh->do(q~
        UPDATE problems SET upload_date = CURRENT_TIMESTAMP WHERE id = ?~, undef,
        $si->{problem_id});
}

sub maybe_status_ok {
    my ($p, $si) = @_;
    $p->{status_ok} or return;
    $dbh->do(q~
        UPDATE contest_problems SET status = ?
        WHERE contest_id = ? AND problem_id = ? AND status <> ?~, undef,
        $cats::problem_st_ready, $si->{contest_id}, $si->{problem_id}, $cats::problem_st_ready);
}

my $settable_verdicts = [ qw(NP AW OK WA PE TL ML WL RE CE SV IS IL MR) ];

sub request_params_frame {
    my ($p) = @_;

    init_template('request_params.html.tt');
    $p->{rid} or return;

    my $si = get_sources_info(request_id => $p->{rid}) or return;
    $si->{is_jury} or return;

    my $limits = { map { $_ => param($_) } grep param($_) && param("set_$_"), @cats::limits_fields };

    my $need_clear_limits = 0 == grep param("set_$_"), @cats::limits_fields;

    if (!$need_clear_limits) {
        my $filtered_limits = CATS::Request::filter_valid_limits($limits);
        my @invalid_limits_keys = grep !exists $filtered_limits->{$_}, keys %$limits;
        if (@invalid_limits_keys) {
            $need_clear_limits = 0;
            msg(1144);
        }
    }

    my $params = {
        state => $cats::st_not_processed,
        # Insert NULL into database to be replaced with contest-default testset.
        testsets => param('testsets') || undef,
        judge_id => (param('set_judge') && param('judge') ? param('judge') : undef),
        points => undef, failed_test => 0,
    };

    if ($p->{retest}) {
        if ($need_clear_limits) {
            $params->{limits_id} = undef;
        } else {
            $params->{limits_id} = CATS::Request::set_limits($si->{limits_id}, $limits);
        }
        CATS::Request::enforce_state($si->{req_id}, $params);
        CATS::Request::delete_limits($si->{limits_id}) if $need_clear_limits && $si->{limits_id};
        maybe_reinstall($p, $si);
        maybe_status_ok($p, $si);
        $dbh->commit;
        $si = get_sources_info(request_id => $si->{req_id});
    }
    if ($p->{clone}) {
        if (!$need_clear_limits) {
            if ($si->{limits_id}) {
                $params->{limits_id} = CATS::Request::clone_limits($si->{limits_id}, $limits);
            } else {
                $params->{limits_id} = CATS::Request::set_limits(undef, $limits);
            }
        }
        my $group_req_id = CATS::Request::clone($si->{req_id}, $si->{contest_id}, $uid, $params);
        maybe_reinstall($p, $si);
        maybe_status_ok($p, $si);
        $dbh->commit;
        return $group_req_id ? $p->redirect(url_f 'request_params', rid => $group_req_id, sid => $sid) : undef;
    }
    my $can_delete = !$si->{is_official} || $is_root || ($si->{account_id} // 0) == $uid;
    $t->param(can_delete => $can_delete);
    if ($p->{delete_request} && $can_delete) {
        CATS::Request::delete($si->{req_id});
        $dbh->commit;
        msg(1056, $si->{req_id});
        return;
    }

    if ($p->{set_tag}) {
        $dbh->do(q~
            UPDATE reqs SET tag = ? WHERE id = ?~, undef,
            $p->{tag}, $si->{req_id});
        $dbh->commit;
        $si->{tag} = Encode::decode_utf8($p->{tag});
    }

    # Reload problem after the successful state change.
    $si = get_sources_info(request_id => $si->{req_id}) if try_set_state($p);

    my $tests = $dbh->selectcol_arrayref(q~
        SELECT rank FROM tests WHERE problem_id = ? ORDER BY rank~, undef,
        $si->{problem_id});
    $t->param(tests => [ map { test_index => $_ }, @$tests ]);

    source_links($si);
    sources_info_param([ $si ]);
    $t->param(settable_verdicts => $settable_verdicts);

    if ($is_root) {
        my $judge_de_bitmap =
            CATS::DB::select_row('judge_de_bitmap_cache', '*', { judge_id => $si->{judge_id} }) ||
            { version => 0, de_bits1 => 0, de_bits2 => 0 };
        my ($des_cond, @des_params) =
            CATS::JudgeDB::dev_envs_condition($judge_de_bitmap, $judge_de_bitmap->{version});

        my $rf = join ', ', map "RDEBC.de_bits$_ AS request_de_bits$_", 1 .. $cats::de_req_bitfields_count;
        my $pf = join ', ', map "PDEBC.de_bits$_ AS problem_de_bits$_", 1 .. $cats::de_req_bitfields_count;

        my $cache = $dbh->selectrow_hashref(qq~
            SELECT
                RDEBC.version AS request_version, $rf,
                PDEBC.version AS problem_version, $pf,
                (CASE WHEN $des_cond THEN 1 ELSE 0 END) AS is_supported
            FROM reqs R
                INNER JOIN problems P ON P.id = R.problem_id
                LEFT JOIN req_de_bitmap_cache RDEBC ON RDEBC.req_id = R.id
                LEFT JOIN problem_de_bitmap_cache PDEBC ON PDEBC.problem_id = P.id
            WHERE
                R.id = ?~, undef,
            @des_params, $si->{req_id});
        $t->param(de_cache => $cache);
    }
}

sub try_set_state {
    my ($p) = @_;
    $p->{set_state} or return;
    grep $_ eq $p->{state}, @$settable_verdicts or return;
    my $state = $CATS::Verdicts::name_to_state->{$p->{state}};

    CATS::Request::enforce_state($p->{rid}, {
        failed_test => $p->{failed_test}, state => $state, points => $p->{points}
    });
    $dbh->commit;
    msg(1055);
    1;
}

sub run_log_frame {
    my ($p) = @_;
    init_template('run_log.html.tt');
    my $rid = $p->{rid} or return;

    my $si = get_sources_info(request_id => $rid)
        or return;
    $si->{is_jury} or return;

    source_links($si);
    sources_info_param([ $si ]);

    if ($p->{delete_log}) {
        $dbh->do(q~
            DELETE FROM log_dumps WHERE req_id = ?~, undef,
            $rid);
        $dbh->commit;
        msg(1159);
    }

    $t->param(get_log_dump($rid));
}

sub diff_runs_frame {
    my ($p) = @_;
    init_template('diff_runs.html.tt');
    $p->{r1} && $p->{r2} or return;

    my $si = get_sources_info(
        request_id => [ $p->{r1}, $p->{r2} ], get_source => 1, encode_source => 1) or return;
    @$si == 2 or return;

    source_links($_) for @$si;
    sources_info_param($si);

    return msg(1155) if grep @{$_->{elements}} > 1, @$si;

    for my $info (@$si) {
        $info->{lines} = [ split "\n", $info->{src} ];
        s/\s*$// for @{$info->{lines}};
    }

    my @diff;

    my $SL = sub { $si->[$_[0]]->{lines}->[$_[1]] || '' };

    my $match = sub { push @diff, { class => 'diff_both', line => $SL->(0, $_[0]) }; };
    my $only_a = sub { push @diff, { class => 'diff_only_a', line => $SL->(0, $_[0]) }; };
    my $only_b = sub { push @diff, { class => 'diff_only_b', line => $SL->(1, $_[1]) }; };

    Algorithm::Diff::traverse_sequences(
        $si->[0]->{lines},
        $si->[1]->{lines},
        {
            MATCH     => $match,  # callback on identical lines
            DISCARD_A => $only_a, # callback on A-only
            DISCARD_B => $only_b, # callback on B-only
        }
    );

    $t->param(diff_lines => \@diff);
}

1;
