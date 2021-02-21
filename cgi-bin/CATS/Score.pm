package CATS::Score;

use strict;
use warnings;

use List::Util qw(max);

use CATS::DB qw(:DEFAULT);
use CATS::Testset;

my $eps = 1e-9;

sub _round {
    my ($points, $round_to) = @_;
    int($points / $round_to + $eps) * $round_to;
}

sub scale_points {
    my ($points, $problem) = @_;
    $points && $problem->{scaled_points} ?
        _round($points * $problem->{scaled_points} / ($problem->{max_points} || 1),
             $problem->{round_points_to} || 0.1) :
    $points && ($problem->{round_points_to} // 0) >= 1 ?
        _round($points, $problem->{round_points_to}) :
    $points;
}

sub get_test_testsets {
    my ($problem, $testset_spec) = @_;
    $problem->{all_testsets} ||= CATS::Testset::get_all_testsets($dbh, $problem->{problem_id});
    CATS::Testset::parse_test_rank($problem->{all_testsets}, $testset_spec);
}

# problem: problem_id, points_testsets, testsets, max_points_def, cpid
sub cache_max_points {
    my ($problem) = @_;
    my $pid = $problem->{problem_id};
    my $max_points = 0;
    my $problem_testsets = $problem->{points_testsets} || $problem->{testsets};
    if ($problem_testsets) {
        my $test_testsets = get_test_testsets($problem, $problem_testsets);
        my $test_points = $dbh->selectall_arrayref(q~
            SELECT rank, points FROM tests WHERE problem_id = ?~, { Slice => {} },
            $pid);
        my %used_testsets;
        for (@$test_points) {
            my $r = $_->{rank};
            exists $test_testsets->{$r} or next;
            my $ts = $test_testsets->{$r};
            $max_points +=
                !$ts || !defined($ts->{points}) ? $_->{points} // 0 :
                $used_testsets{$ts->{name}}++ ? 0 :
                $ts->{points};
        }
    }
    else {
        $max_points = $dbh->selectrow_array(q~
            SELECT SUM(points) FROM tests WHERE problem_id = ?~, undef,
            $pid);
    }
    $max_points ||= $problem->{max_points_def} || 1;
    if ($problem->{cpid}) {
        $dbh->do(q~
            UPDATE contest_problems SET max_points = ?
            WHERE id = ? AND (max_points IS NULL OR max_points <> ?)~, undef,
            $max_points, $problem->{cpid}, $max_points);
    }
    $max_points;
}


sub dependencies_accepted {
    my ($all_testsets, $ts, $accepted_tests, $cache) = @_;
    return 1 if !$ts->{depends_on} or $cache->{$ts->{name}};
    my $tests = $ts->{parsed_depends_on} //=
        CATS::Testset::parse_test_rank($all_testsets, $ts->{depends_on}, undef, include_deps => 1);
    $accepted_tests->{$_} or return 0 for keys %$tests;
    return $cache->{$ts->{name}} = 1;
}

sub align_by_point {
    my ($data, $field, $char) = @_;
    $char //= '0';
    my $max_frac_len = 0;
    my $frac_re = qr/\.(\d*)$/;
    for my $row (@$data) {
        $max_frac_len = max(length($1), $max_frac_len) if $row->{$field} =~ $frac_re;
    }
    $max_frac_len or return;

    for my $row (@$data) {
        $row->{$field} .= $row->{$field} =~ $frac_re ?
            $char x ($max_frac_len - length($1)) : '.' . ($char x $max_frac_len);
    }
}

1;
