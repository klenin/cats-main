package CATS::Score;

use strict;
use warnings;

use CATS::DB qw(:DEFAULT);
use CATS::Testset;

sub _round { int($_[0] * 10 + 0.5) / 10 }

sub scale_points {
    my ($points, $problem) = @_;
    $points && (
    $problem->{scaled_points} ?
        _round($points * $problem->{scaled_points} / ($problem->{max_points} || 1)) : $points);

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

1;
