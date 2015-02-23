package CATS::Testset;

use strict;
use warnings;

use CATS::DB qw($dbh);


sub parse_test_rank
{
    my ($all_testsets, $rank_spec, $on_error) = @_;
    my (%result, %used, $rec);
    $rec = sub {
        my ($r, $scoring_group) = @_;
        $r =~ s/\s+//g;
        # Rank specifier is a comma-separated list, each element being one of:
        # * test number,
        # * range of test numbers,
        # * testset name.
        for (split ',', $r) {
            if (/^[a-zA-Z][a-zA-Z0-9_]*$/) {
                my $testset = $all_testsets->{$_} or die \"Unknown testset '$_'";
                $used{$_}++ and die \"Recursive usage of testset '$_'";
                my $sg = $scoring_group;
                if ($testset->{points} || $testset->{hide_details}) {
                    die \"Nested scoring group '$_'" if $sg;
                    $sg = $testset;
                    $sg->{test_count} = 0;
                }
                $rec->($testset->{tests}, $sg);
            }
            elsif (/^(\d+)(?:-(\d+))?$/) {
                my ($from, $to) = ($1, $2 || $1);
                $from <= $to or die \"from > to";
                for my $t ($from..$to) {
                    die \"Ambiguous scoring group for test $t"
                        if $scoring_group && $result{$t} && $result{$t} ne $scoring_group;
                    $result{$t} = $scoring_group;
                    ++$scoring_group->{test_count} if $scoring_group;
                }
            }
            else {
                die \"Bad element '$_'";
            }
        }
    };
    eval { $rec->($rank_spec); %result or die \'Empty rank specifier'; }
        or $on_error && $on_error->(ref $@ ? "${$@} in rank spec '$rank_spec'" : $@);
    \%result;
}


sub get_all_testsets
{
    $dbh->selectall_hashref(qq~
        SELECT id, name, tests, points, comment, hide_details
        FROM testsets WHERE problem_id = ?~,
        'name', undef,
        $_[0]) || {};
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
    my @all_tests = @{$dbh->selectcol_arrayref(qq~
        SELECT rank FROM tests WHERE problem_id = ? ORDER BY rank~, undef,
        $pid
    )};
    $testsets or return map { $_ => undef } @all_tests;

    if ($update && ($orig_testsets || '') ne $testsets) {
        $dbh->do(q~
            UPDATE reqs SET testsets = ? WHERE id = ?~, undef,
            $testsets, $rid);
        $dbh->commit;
    }

    my %tests = %{parse_test_rank(get_all_testsets($pid), $testsets)};
    map { exists $tests{$_} ? ($_ => $tests{$_}) : () } @all_tests;
}


1;
