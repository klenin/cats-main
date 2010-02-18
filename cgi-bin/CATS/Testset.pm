package CATS::Testset;

use strict;
use warnings;

use CATS::DB qw($dbh);

sub parse_test_rank
{
    my ($rank_spec) = @_;
    my @result;
    for (split ',', $rank_spec)
    {
        $_ =~ /^\s*(\d+)(?:-(\d+))?\s*$/
            or return ();
        my ($from, $to) = ($1, $2 || $1);
        $from <= $to or next;
        push @result, ($from..$to);
    }
    @result;
}

 
sub get_testset
{
    my ($rid, $update) = @_;
    my ($pid, $testsets) = $dbh->selectrow_array(q~
        SELECT R.problem_id, COALESCE(R.testsets, CP.testsets)
        FROM reqs R
        INNER JOIN contest_problems CP ON
            CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
        WHERE R.id = ?~, undef,
        $rid);
    my @tests = @{$dbh->selectcol_arrayref(qq~
        SELECT rank FROM tests WHERE problem_id = ? ORDER BY rank~, undef,
        $pid
    )};
    $testsets or return @tests;

    if ($update)
    {
        $dbh->do(q~
            UPDATE reqs SET testsets = ? WHERE id = ?~, undef,
            $testsets, $rid);
        $dbh->commit;
    }

    my %tests_by_testset;
    my %sel_testsets;
    for (split /\s+/, $testsets)
    {
        $sel_testsets{$_} = 1;
        @tests_by_testset{parse_test_rank($_)} = undef;
    }

    my $all_testsets = $dbh->selectall_arrayref(q~
        SELECT name, tests FROM testsets WHERE problem_id = ?~, { Slice => {} },
        $pid);
    for (@$all_testsets)
    {
        next unless exists $sel_testsets{$_->{name}};
        @tests_by_testset{parse_test_rank($_->{tests})} = undef;
    }
    return grep exists $tests_by_testset{$_}, @tests;
}


1;
