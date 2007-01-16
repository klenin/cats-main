package CATS::RankTable;

use lib '..';
use strict;
use warnings;
use Encode;

use CATS::Constants;
use CATS::Misc qw($dbh $t $is_jury url_f);

use fields qw(contest_list hide_ooc hide_virtual);


sub new
{
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}


sub cache_max_points
{
    my ($pid) = @_;
    my ($max_points) = $dbh->selectrow_array(q~
        SELECT SUM(points) FROM tests WHERE problem_id = ?~, undef, $pid);
    $dbh->do(q~UPDATE problems SET max_points = ? WHERE id = ?~, undef, $max_points, $pid);
    $max_points;
}


sub get_problem_ids
{
    my ($contest_list, $show_points) = @_;
    # соответствующее требование: в одном чемпионате задача не должна дублироваться обеспечивается
    # при помощи UNIQUE(c,p)
    my $problems = $dbh->selectall_arrayref(qq~
        SELECT
            CP.id, CP.problem_id, CP.code, CP.contest_id, CATS_DATE(C.start_date) AS start_date,
            CATS_SYSDATE() - C.start_date AS since_start, C.local_only, P.max_points, P.title
        FROM
            contest_problems CP INNER JOIN contests C ON C.id = CP.contest_id
            INNER JOIN problems P ON P.id = CP.problem_id
        WHERE CP.contest_id IN ($contest_list) AND CP.status < ?
        ORDER BY C.start_date, CP.code~, { Slice => {} },
        $cats::problem_st_hidden
    );

    my $w = int(50 / (@$problems + 1));
    $w = $w < 3 ? 3 : $w > 10 ? 10 : $w;
    $_->{column_width} = $w for @$problems;

    my @contests = ();
    my $prev_cid = -1;
    my $need_commit = 0;
    my $max_total_points = 0;
    for (@$problems)
    {
        if ($_->{contest_id} != $prev_cid)
        {
            $_->{start_date} =~ /^\s*(\S+)/;
            push @contests, { start_date => $1, count => 1 };
            $prev_cid = $_->{contest_id};
        }
        else
        {
            $contests[$#contests]->{count}++;
        }
        # оптимизация: не выводить tooltip в local_only турнирах, чтобы сэкономить запрос
        $_->{title} = '' if ($_->{since_start} < 0 || $_->{local_only}) && !$is_jury;
        $_->{problem_text} = url_f('problem_text', cpid => $_->{id});
        if ($show_points && !$_->{max_points})
        {
            $_->{max_points} = cache_max_points($_->{problem_id});
            $need_commit = 1;
        }
        $max_total_points += $_->{max_points} || 0;
    }
    $dbh->commit if $need_commit;

    $t->param(
        problems => $problems,
        problem_column_width => $w,
        contests => [ @contests ],
        many_contests => @contests > 1,
        max_total_points => $max_total_points
    );
    
    map { $_->{problem_id} } @$problems;
}


1;
