package CATS::RunDetails;

use strict;
use warnings;

BEGIN
{
    no strict;
    use Exporter;
    @ISA = qw(Exporter);
    @EXPORT = qw(
        get_contest_info
        get_log_dump
        get_run_info
        source_encodings
        source_links
    );
}

use CGI qw(param url_param);
use CATS::DB;
use CATS::Utils qw(state_to_display url_function);
use CATS::Misc qw($sid $t url_f);

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


1;
