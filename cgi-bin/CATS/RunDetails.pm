package CATS::RunDetails;

use strict;
use warnings;

use Algorithm::Diff;
use CGI qw(param span url_param);
use CATS::DB;
use CATS::Utils qw(escape_html state_to_display url_function);
use CATS::Misc qw($is_jury $sid $t $uid init_template msg upload_source url_f);
use CATS::Data qw(is_jury_in_contest enforce_request_state);
use CATS::IP;
use CATS::DevEnv;
use CATS::RankTable;


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
    my ($contest, $req) = @_;
    my $points = $contest->{points};

    my %run_details;
    my $rd_fields = join ', ', (
         qw(test_rank result),
         ($contest->{show_test_resources} ? qw(time_used memory_used disk_used) : ()),
         ($contest->{show_checker_comment} ? qw(checker_comment) : ()),
    );

    my $c = $dbh->prepare(qq~
        SELECT $rd_fields FROM req_details WHERE req_id = ? ORDER BY test_rank~);
    $c->execute($req->{req_id});
    my $last_test = 0;
    my $total_points = 0;
    my %testset = CATS::Testset::get_testset($req->{req_id});
    $contest->{show_points} ||= 0 < grep $_, values %testset;
    my %used_testsets;

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
        $last_test = $row->{test_rank};
        my $accepted = $row->{result} == $cats::st_accepted;
        my $p = $accepted ? $points->[$row->{test_rank} - 1] : 0;
        if (my $ts = $testset{$last_test}) {
            $used_testsets{$ts->{name}} = $ts;
            push @{$ts->{list} ||= []}, $last_test;
            $p = "=> $ts->{name}";
            $total_points += $ts->{earned_points} = $ts->{points}
                if $accepted && ++$ts->{accepted_count} == $ts->{test_count};
        }
        elsif ($accepted && $req->{partial_checker}) {
            $total_points += $p = CATS::RankTable::get_partial_points($row, $p);
        }
        else {
            $total_points += ($p || 0);
        }
        $run_details{$last_test} = {
            state_to_display($row->{result}),
            map({ $_ => $contest->{$_} }
                qw(show_test_resources show_checker_comment)),
            %$row, show_points => $contest->{show_points}, points => $p,
        };
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
        run_details => [ map $run_row->($_), 1..$last_test ],
        testsets => [ sort { $a->{list}[0] <=> $b->{list}[0] } values %used_testsets ],
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


sub get_nearby_attempt
{
    my ($si, $prevnext, $cmp, $ord, $diff) = @_;
    my $na = $dbh->selectrow_hashref(qq~
        SELECT id, submit_time FROM reqs
          WHERE account_id = ? AND problem_id = ? AND id $cmp ?
          ORDER BY id $ord ROWS 1~, { Slice => {} },
        $si->{account_id}, $si->{problem_id}, $si->{req_id}
    ) or return;
    for ($na->{submit_time}) {
        s/\s*$//;
        # If the date is the same with the current run, display only time.
        my ($n_date, $n_time) = /^(\d+\.\d+\.\d+\s+)(.*)$/;
        $si->{"${prevnext}_attempt_time"} = $si->{submit_time} =~ /^$n_date/ ? $n_time : $_;
    }
    my $f = url_param('f') || 'run_log';
    my @p;
    if ($f eq 'diff_runs') {
        for (1..2) {
            my $r = CGI::url_param("r$_") || 0;
            push @p, "r$_" => ($r == $si->{req_id} ? $na->{id} : $r);
        }
    }
    else {
        @p = (rid => $na->{id});
    }
    $si->{"href_${prevnext}_attempt"} = url_f($f, @p);
    $si->{href_diff_runs} = url_f('diff_runs', r1 => $na->{id}, r2 => $si->{req_id}) if $diff;
}


# Load informatin about one or several runs..
# Parameters: request_id, may be either scalar or array ref.
sub get_sources_info
{
    my %p = @_;
    my $rid = $p{request_id} or return;

    my @req_ids = ref $rid eq 'ARRAY' ? @$rid : ($rid);
    @req_ids = map +$_, grep $_ && /^\d+$/, @req_ids or return;

    my $src = $p{get_source} ? ' S.src, DE.syntax,' : '';
    my $req_id_list = join ', ', @req_ids;
    my $pc_sql = $p{partial_checker} ? CATS::RankTable::partial_checker_sql() . ',' : '';
    my $result = $dbh->selectall_arrayref(qq~
        SELECT
            S.req_id,$src S.fname AS file_name, S.de_id,
            R.account_id, R.contest_id, R.problem_id, R.judge_id,
            R.state, R.failed_test,
            R.submit_time,
            R.test_time,
            R.result_time,
            DE.description AS de_name,
            A.team_name, A.last_ip,
            P.title AS problem_name, $pc_sql
            C.title AS contest_name,
            COALESCE(R.testsets, CP.testsets) AS testsets,
            C.id AS contest_id, CP.id AS cp_id,
            CA.id AS ca_id
        FROM sources S
            INNER JOIN reqs R ON R.id = S.req_id
            INNER JOIN default_de DE ON DE.id = S.de_id
            INNER JOIN accounts A ON A.id = R.account_id
            INNER JOIN problems P ON P.id = R.problem_id
            INNER JOIN contests C ON C.id = R.contest_id
            INNER JOIN contest_problems CP ON CP.contest_id = C.id AND CP.problem_id = P.id
            INNER JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = A.id
        WHERE req_id IN ($req_id_list)~, { Slice => {} });

    my $official = $p{get_source} && !$is_jury && CATS::Contest::current_official;
    for my $r (@$result) {
        $r = {
            %$r, state_to_display($r->{state}),
            CATS::IP::linkify_ip(CATS::IP::filter_ip $r->{last_ip}),
            href_stats => url_f('user_stats', uid => $r->{account_id}),
            href_send_message => url_f('send_message_box', caid => $r->{ca_id}),
        };
        # Just hour and minute from testing start and finish timestamps.
        ($r->{"${_}_short"} = $r->{$_}) =~ s/^(.*)\s+(\d\d:\d\d)\s*$/$2/
            for qw(test_time result_time);
        get_nearby_attempt($r, 'prev', '<', 'DESC', 1);
        get_nearby_attempt($r, 'next', '>', 'ASC', 0);
        # During the official contest, viewing sources from other contests
        # is disallowed to prevent cheating.
        if ($official && $official->{id} != $r->{contest_id}) {
            $r->{src} = res_str(123, $official->{title});
        }
    }

    return ref $rid ? $result : $result->[0];
}

sub run_details_frame
{
    init_template('run_details.html.tt');

    my $rid = url_param('rid') or return;
    my $rids = [ grep /^\d+$/, split /,/, $rid ];
    my $si = get_sources_info(request_id => $rids, partial_checker => 1) or return;

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
            $_ = get_sources_info(request_id => $_->{req_id}, partial_checker => 1) or next;
        }

        source_links($_, $is_jury);
        $contest = get_contest_info($_, $is_jury && !url_param('as_user'))
            if $_->{contest_id} != $contest->{id};
        push @runs,
            $_->{state} == $cats::st_compilation_error ?
            { get_log_dump($_->{req_id}, 1) } : get_run_info($contest, $_);
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
        or return $show_msg && msg(126);
    my $se = param('src_enc') || 'WINDOWS-1251';
    if (source_encodings()->{$se} && $sources_info->{file_name} !~ m/\.zip$/) {
        Encode::from_to($sources_info->{src}, $se, 'utf-8');
    }
    ($sources_info, $is_jury);
}


sub view_source_frame
{
    init_template('view_source.html.tt');
    my ($sources_info, $is_jury) = prepare_source(1);
    $sources_info or return;
    my $replace_source = param('replace_source');
    my $de_id = param('de_id');
    my $set = join ', ', ($replace_source ? 'src = ?' : ()) , ($de_id ? 'de_id = ?' : ());
    if ($is_jury && $set) {
        my $s = $dbh->prepare(qq~
            UPDATE sources SET $set WHERE req_id = ?~);
        my $i = 0;
        if ($replace_source) {
            my $src = upload_source('replace_source') or return;
            $s->bind_param(++$i, $src, { ora_type => 113 } ); # blob
            $sources_info->{src} = $src;
        }
        $s->bind_param(++$i, $de_id) if $de_id;
        $s->bind_param(++$i, $sources_info->{req_id});
        $s->execute;
        $dbh->commit;
    }
    if ($sources_info->{file_name} =~ m/\.zip$/) {
        $sources_info->{src} = sprintf 'ZIP, %d bytes', length ($sources_info->{src});
    }
    source_links($sources_info, $is_jury);
    /^[a-z]+$/i and $sources_info->{syntax} = $_ for param('syntax');
    $sources_info->{src_lines} = [ map {}, split("\n", $sources_info->{src}) ];
    $t->param(sources_info => [ $sources_info ]);

    if ($is_jury) {
        my $de_list = CATS::DevEnv->new($dbh, active_only => 1);
        if ($de_id) {
            $sources_info->{de_id} = $de_id;
            $sources_info->{de_name} = $de_list->by_id($de_id)->{description};
        }
        $t->param(de_list => [
            map {
                de_id => $_->{id},
                de_name => $_->{description},
                selected => $_->{id} == $sources_info->{de_id},
            }, @{$de_list->{_de_list}}
        ]);
    }
}


sub download_source_frame
{
    my ($si, $is_jury) = prepare_source(0);
    unless ($si) {
        init_template('view_source.html.tt');
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
    init_template('run_log.html.tt');
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
    init_template('diff_runs.html.tt');
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
