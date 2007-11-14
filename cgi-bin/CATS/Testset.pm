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
    my ($cid, $pid) = @_;
    my ($testsets) = $dbh->selectrow_array(q~
        SELECT testsets FROM contest_problems
        WHERE contest_id = ? AND problem_id = ?~, undef,
        $cid, $pid);
    my @tests = @{$dbh->selectcol_arrayref(qq~
        SELECT rank FROM tests WHERE problem_id = ? ORDER BY rank~, undef,
        $pid
    )};
    $testsets or return @tests;

    my %sel_testsets;
    @sel_testsets{split /\s+/, $testsets} = undef;

    my %tests_by_testset;
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
