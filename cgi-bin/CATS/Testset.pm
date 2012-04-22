package CATS::Testset;

use strict;
use warnings;

use CATS::DB qw($dbh);

sub parse_test_rank
{
    my ($testsets, $rank_spec, $on_error) = @_;
    my (@result, %used, $rec);
    $rec = sub {
        my ($r) = @_;
        $r =~ s/\s+//g;
        # Rank specifier is a comma-separated list, each element being one of:
        # * test number,
        # * range of test numbers,
        # * testset name.
        for (split ',', $r) {
            if (/^[a-zA-Z][a-zA-Z0-9_]*$/) {
                my $testset = $testsets->{$_} or die \"Unknown testset '$_'";
                $used{$_}++ and die \"Recursive usage of testset '$_'";
                $rec->($testset->{tests});
            }
            elsif (/^(\d+)(?:-(\d+))?$/) {
                my ($from, $to) = ($1, $2 || $1);
                $from <= $to or die \"from > to";
                push @result, $from..$to;
            }
            else {
                die \"Bad element '$_'";
            }
        }
    };
    eval { $rec->($rank_spec); 1 }
        or $on_error && $on_error->(ref $@ ? "${$@} in rank spec '$rank_spec'" : $@);
    @result;
}

sub get_testset
{
    my ($rid, $update) = @_;
    my ($pid, $orig_testsets, $testsets) = $dbh->selectrow_array(q~
        SELECT R.problem_id, R.testsets, COALESCE(R.testsets, CP.testsets)
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

    if ($update && ($orig_testsets || '') ne $testsets) {
        $dbh->do(q~
            UPDATE reqs SET testsets = ? WHERE id = ?~, undef,
            $testsets, $rid);
        $dbh->commit;
    }

    my $all_testsets = $dbh->selectall_hashref(q~
        SELECT name, tests FROM testsets WHERE problem_id = ?~, 'name', undef,
        $pid);
    my %tests_by_testset;
    @tests_by_testset{parse_test_rank($all_testsets, $testsets)} = undef;
    return grep exists $tests_by_testset{$_}, @tests;
}


1;
