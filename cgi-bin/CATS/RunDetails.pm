package CATS::RunDetails;

use strict;
use warnings;

use Algorithm::Diff;
use CGI qw(param span url_param);
use CATS::DB;
use CATS::Utils qw(escape_html state_to_display url_function);
use CATS::Misc qw($is_jury $sid $t $uid init_template url_f);
use CATS::Data qw(is_jury_in_contest enforce_request_state get_sources_info);


sub get_judge_name
{
    my ($judge_id) = @_ or return;
    scalar $dbh->selectrow_array(qq~
      SELECT nick FROM judges WHERE id = ?~, undef,
      $judge_id);
}


sub source_encodings { {'UTF-8' => 1, 'WINDOWS-1251' => 1, 'KOI8-R' => 1, 'CP866' => 1, 'UCS-2LE' => 1} }


sub source_links
{
    my ($si, $is_jury) = @_;
    my ($current_link) = url_param('f') || '';

    $si->{href_contest} =
        url_function('problems', cid => $si->{contest_id}, sid => $sid);
    $si->{href_problem} =
        url_function('problem_text', cpid => $si->{cp_id}, cid => $si->{contest_id}, sid => $sid);
    for (qw/run_details view_source run_log download_source/) {
        $si->{"href_$_"} = url_f($_, rid => $si->{req_id});
        $si->{"href_class_$_"} = $_ eq $current_link ? 'current_link' : '';
    }
    $si->{is_jury} = $is_jury;
    $t->param(is_jury => $is_jury);
    if ($is_jury && $si->{judge_id}) {
        $si->{judge_name} = get_judge_name($si->{judge_id});
    }
    my $se = param('src_enc') || param('comment_enc') || 'WINDOWS-1251';
    $t->param(source_encodings =>
        [ map {{ enc => $_, selected => $_ eq $se }} sort keys %{source_encodings()} ]);
}


sub get_run_info
{
    my ($contest, $rid) = @_;
    my $points = $contest->{points};

    my %run_details;
    my $rd_fields = join ', ', (
         qw(test_rank result),
         ($contest->{show_test_resources} ? qw(time_used memory_used disk_used) : ()),
         ($contest->{show_checker_comment} ? qw(checker_comment) : ()),
    );

    my $c = $dbh->prepare(qq~
        SELECT $rd_fields FROM req_details WHERE req_id = ? ORDER BY test_rank~);
    $c->execute($rid);
    my $last_test = 0;
    my $total_points = 0;

    while (my $row = $c->fetchrow_hashref()) {
        $_ and $_ = sprintf('%.3g', $_) for $row->{time_used};
        if ($contest->{show_checker_comment}) {
            my $d = $row->{checker_comment} || '';
            my $enc = param('comment_enc') || '';
            source_encodings()->{$enc} or $enc = 'UTF-8';
            # Comment may be non-well-formed utf8
            $row->{checker_comment} = Encode::decode($enc, $d, Encode::FB_QUIET);
            $row->{checker_comment} .= '...' if $d ne '';
        }

        my $prev_test = $last_test;
        my $accepted = $row->{result} == $cats::st_accepted;
        my $p = $accepted ? $points->[$row->{test_rank} - 1] : 0;
        $run_details{$last_test = $row->{test_rank}} = {
            state_to_display($row->{result}),
            map({ $_ => $contest->{$_} }
                qw(show_test_resources show_checker_comment)),
            %$row, show_points => $contest->{show_points}, points => $p,
        };
        $total_points += ($p || 0);
        # When tests are run in random order, and the user looks at the run details
        # while the testing is in progress, he may be able to see 'OK' result
        # for the test ranked above the (unknown at the moment) first failing test.
        # Prevent this by stopping output at the first failed OR not-run-yet test.
        last if
            !$contest->{show_all_tests} &&
            (!$accepted || $prev_test != $last_test - 1);
    }
    # Output 'not processed' for tests we do not plan to run, but must still display.
    if ($contest->{show_all_tests} && !$contest->{run_all_tests}) {
        $last_test = @$points;
    }
    my %testset;
    @testset{CATS::Testset::get_testset($rid)} = undef;

    my $run_row = sub {
        my ($rank) = @_;
        return $run_details{$rank} if exists $run_details{$rank};
        return () unless $contest->{show_all_tests};
        my %r = ( test_rank => $rank );
        $r{exists $testset{$rank} ? 'not_processed' : 'not_in_testset'} = 1;
        return \%r;
    };
    return {
        %$contest,
        total_points => $total_points,
        run_details => [ map $run_row->($_), 1..$last_test ]
    };
}


sub get_contest_info
{
    my ($si, $jury_view) = @_;

    my $contest = $dbh->selectrow_hashref(qq~
        SELECT
            id, run_all_tests, show_all_tests, show_test_resources,
            show_checker_comment
            FROM contests WHERE id = ?~, { Slice => {} },
        $si->{contest_id});

    $contest->{$_} ||= $jury_view
        for qw(show_all_tests show_test_resources show_checker_comment);

    my $p = $contest->{points} =
        $contest->{show_all_tests} ?
        $dbh->selectcol_arrayref(qq~
            SELECT points FROM tests WHERE problem_id = ? ORDER BY rank~, undef,
            $si->{problem_id})
        : [];
    $contest->{show_points} = 0 != grep defined $_ && $_ > 0, @$p;
    $contest;
}


sub get_log_dump
{
    my ($rid, $compile_error) = @_;
    my ($dump) = $dbh->selectrow_array(qq~
        SELECT dump FROM log_dumps WHERE req_id = ?~, undef,
        $rid) or return ();
    $dump = Encode::decode('CP1251', $dump);
    $dump =~ s/(?:.|\n)+spawner\\sp\s((?:.|\n)+)compilation error\n/$1/m
        if $compile_error;
    return (judge_log_dump => $dump);
}


sub run_details_frame
{
    init_template('main_run_details.htm');

    my $rid = url_param('rid') or return;
    my $rids = [ grep /^\d+$/, split /,/, $rid ];
    my $si = get_sources_info(request_id => $rids) or return;

    my @runs;
    my ($is_jury, $contest) = (0, { id => 0 });
    for (@$si) {
        $is_jury = is_jury_in_contest(contest_id => $_->{contest_id})
            if $_->{contest_id} != $contest->{id};
        $is_jury || $uid == $_->{account_id} or next;

        if ($is_jury && param('retest')) {
            enforce_request_state(
                request_id => $_->{req_id},
                state => $cats::st_not_processed,
                testsets => param('testsets'));
            $_ = get_sources_info(request_id => $_->{req_id}) or next;
        }

        source_links($_, $is_jury);
        $contest = get_contest_info($_, $is_jury && !url_param('as_user'))
            if $_->{contest_id} != $contest->{id};
        push @runs,
            $_->{state} == $cats::st_compilation_error ?
            { get_log_dump($_->{req_id}, 1) } : get_run_info($contest, $_->{req_id});
    }
    $t->param(sources_info => $si, runs => \@runs);
}


sub prepare_source
{
    my ($show_msg) = @_;
    my $rid = url_param('rid') or return;

    my $sources_info = get_sources_info(request_id => $rid, get_source => 1)
        or return;

    my $is_jury = is_jury_in_contest(contest_id => $sources_info->{contest_id});
    $is_jury || $sources_info->{account_id} == ($uid || 0)
        or return ($show_msg && msg(126));
    my $se = param('src_enc') || 'WINDOWS-1251';
    if ($se && source_encodings()->{$se} && $sources_info->{file_name} !~ m/\.zip$/) {
        Encode::from_to($sources_info->{src}, $se, 'utf-8');
    }
    ($sources_info, $is_jury);
}


sub view_source_frame
{
    init_template('main_view_source.htm');
    my ($sources_info, $is_jury) = prepare_source(1);
    $sources_info or return;
    if ($is_jury && param('replace_source')) {
        my $src = upload_source('replace_source') or return;
        my $s = $dbh->prepare(q~
            UPDATE sources SET src = ? WHERE req_id = ?~);
        $s->bind_param(1, $src, { ora_type => 113 } ); # blob
        $s->bind_param(2, $sources_info->{req_id} );
        $s->execute;
        $dbh->commit;
        $sources_info->{src} = $src;
    }
    if ($sources_info->{file_name} =~ m/\.zip$/) {
        $sources_info->{src} = sprintf 'ZIP, %d bytes', length ($sources_info->{src});
    }
    source_links($sources_info, $is_jury);
    /^[a-z]+$/i and $sources_info->{syntax} = $_ for param('syntax');
    $sources_info->{src_lines} = [ map {}, split("\n", $sources_info->{src}) ];
    $t->param(sources_info => [ $sources_info ]);
}


sub download_source_frame
{
    my ($si, $is_jury) = prepare_source(0);
    unless ($si) {
        init_template('main_view_source.htm');
        return;
    }

    $si->{file_name} =~ m/\.([^.]+)$/;
    my $ext = $1 || 'unknown';
    binmode(STDOUT, ':raw');
    print STDOUT CGI::header(
        -type => ($ext eq 'zip' ? 'application/zip' : 'text/plain'),
        -content_disposition => "inline;filename=$si->{req_id}.$ext");
    print STDOUT $si->{src};
}


sub try_set_state
{
    my ($si, $rid) = @_;
    defined param('set_state') or return;
    my $state = {
        not_processed =>         $cats::st_not_processed,
        accepted =>              $cats::st_accepted,
        wrong_answer =>          $cats::st_wrong_answer,
        presentation_error =>    $cats::st_presentation_error,
        time_limit_exceeded =>   $cats::st_time_limit_exceeded,
        memory_limit_exceeded => $cats::st_memory_limit_exceeded,
        runtime_error =>         $cats::st_runtime_error,
        compilation_error =>     $cats::st_compilation_error,
        security_violation =>    $cats::st_security_violation,
        ignore_submit =>         $cats::st_ignore_submit,
    }->{param('state')};
    defined $state or return;

    my $failed_test = sprintf '%d', param('failed_test') || '0';
    enforce_request_state(
        request_id => $rid, failed_test => $failed_test, state => $state);
    my %st = state_to_display($state);
    while (my ($k, $v) = each %st) {
        $si->{$k} = $v;
    }
    $si->{failed_test} = $failed_test;
    1;
}


sub run_log_frame
{
    init_template('main_run_log.htm');
    my $rid = url_param('rid') or return;

    # HACK: To avoid extra database access, require the user
    # to be jury not only in the contest of the problem to be viewed,
    # but in the current contest as well.
    $is_jury or return;

    my $si = get_sources_info(request_id => $rid)
        or return;
    is_jury_in_contest(contest_id => $si->{contest_id})
        or return;

    # Reload problem after the successful state change.
    $si = get_sources_info(request_id => $rid)
        if try_set_state($si, $rid);
    $t->param(sources_info => [$si]);

    source_links($si, 1);
    $t->param(get_log_dump($rid));

    my $tests = $dbh->selectcol_arrayref(qq~
        SELECT rank FROM tests WHERE problem_id = ? ORDER BY rank~, undef,
        $si->{problem_id});
    $t->param(tests => [ map {test_index => $_}, @$tests ]);
}


sub diff_runs_frame
{
    init_template('main_diff_runs.htm');
    $is_jury or return;

    my $si = get_sources_info(
        request_id => [ param('r1'), param('r2') ],
        get_source => 1
    ) or return;
    @$si == 2 or return;

    # User must be jury in contests of both compared problems.
    # Check for jury only once if the contest is the same.
    my ($cid1, $cid2) = map $_->{contest_id}, @$si;
    is_jury_in_contest(contest_id => $cid1)
        or return;
    $cid1 == $cid2 || is_jury_in_contest(contest_id => $cid2)
        or return;

    source_links($_, 1) for @$si;

    for my $info (@$si) {
        $info->{lines} = [ split "\n", $info->{src} ];
        s/\s*$// for @{$info->{lines}};
    }

    my @diff;

    my $SL = sub { $si->[$_[0]]->{lines}->[$_[1]] || '' };

    my $match = sub { push @diff, escape_html($SL->(0, $_[0])) . "\n"; };
    my $only_a = sub { push @diff, span({class=>'diff_only_a'}, escape_html($SL->(0, $_[0])) . "\n"); };
    my $only_b = sub { push @diff, span({class=>'diff_only_b'}, escape_html($SL->(1, $_[1])) . "\n"); };

    Algorithm::Diff::traverse_sequences(
        $si->[0]->{lines},
        $si->[1]->{lines},
        {
            MATCH     => $match,  # callback on identical lines
            DISCARD_A => $only_a, # callback on A-only
            DISCARD_B => $only_b, # callback on B-only
        }
    );

    $t->param(
        sources_info => $si,
        diff_lines => [ map {line => $_}, @diff ]
    );
}


1;
