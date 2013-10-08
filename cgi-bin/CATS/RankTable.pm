package CATS::RankTable;

use lib '..';
use strict;
use warnings;
use Encode;

use CATS::Web qw(param url_param);
use List::Util qw(max min sum);

use CATS::Constants;
use CATS::DB;
use CATS::Testset;
use CATS::Misc qw(
    $t $is_jury $is_team $virtual_diff_time $cid $uid url_f $is_virtual $contest cats_dir
    get_flag);

use fields qw(
    contest_list hide_ooc hide_virtual show_points frozen
    title has_practice not_started filter use_cache
    rank problems problems_idx show_all_results show_prizes
);


sub new
{
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}


sub get_test_testsets
{
    my ($problem, $testset_spec) = @_;
    $problem->{all_testsets} ||= CATS::Testset::get_all_testsets($problem->{problem_id});
    CATS::Testset::parse_test_rank($problem->{all_testsets}, $testset_spec);
}

sub cache_max_points
{
    my ($problem) = @_;
    my $pid = $problem->{problem_id};
    my $max_points = 0;
    if ($problem->{testsets}) {
        my $test_testsets = get_test_testsets($problem, $problem->{testsets});
        my $test_points = $dbh->selectall_arrayref(q~
            SELECT rank, points FROM tests WHERE problem_id = ?~, { Slice => {} },
            $pid);
        my %used_testsets;
        for (@$test_points) {
            my $r = $_->{rank};
            exists $test_testsets->{$r} or next;
            my $t = $test_testsets->{$r};
            $max_points += !$t ? $_->{points} : $used_testsets{$t->{name}}++ ? 0 : $t->{points};
        }
    }
    else {
        $max_points = $dbh->selectrow_array(q~
            SELECT SUM(points) FROM tests WHERE problem_id = ?~, undef, $pid);
    }
    $dbh->do(q~
        UPDATE problems SET max_points = ? WHERE id = ?~, undef, $max_points, $pid);
    $max_points;
}


sub partial_checker_sql {
    my $checker_types = join ', ',
        grep $cats::source_modules{$_} == $cats::checker_module, keys %cats::source_modules;
    qq~
        CASE COALESCE(
            (SELECT PS.stype FROM problem_sources PS
                WHERE PS.problem_id = P.id AND PS.stype IN ($checker_types)),
            (SELECT PS.stype FROM problem_sources PS
                INNER JOIN problem_sources_import PSI ON PSI.guid = PS.guid
                WHERE PSI.problem_id = P.id AND PS.stype IN ($checker_types)))
        WHEN $cats::partial_checker THEN 1 ELSE 0
        END AS partial_checker~;
}


sub get_problems
{
    (my CATS::RankTable $self) = @_;
    my $problems = $self->{problems} = $dbh->selectall_arrayref(qq~
        SELECT
            CP.id, CP.problem_id, CP.code, CP.contest_id, CP.testsets, C.start_date,
            CAST(CURRENT_TIMESTAMP - C.start_date AS DOUBLE PRECISION) AS since_start,
            C.local_only, P.max_points, P.title, @{[ partial_checker_sql ]}
        FROM
            contest_problems CP INNER JOIN contests C ON C.id = CP.contest_id
            INNER JOIN problems P ON P.id = CP.problem_id
        WHERE
            CP.contest_id IN ($self->{contest_list}) AND CP.status < ?
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
        if ($_->{contest_id} != $prev_cid) {
            $_->{start_date} =~ /^(\S+)/;
            push @contests, { start_date => $1, count => 1 };
            $prev_cid = $_->{contest_id};
        }
        else {
            $contests[$#contests]->{count}++;
        }
        # Optimization: do not output tooltip in local_only contests to avoid extra query.
        $_->{title} = '' if ($_->{since_start} < 0 || $_->{local_only}) && !$is_jury;
        $_->{problem_text} = url_f('problem_text', cpid => $_->{id});
        if ($self->{show_points} && !$_->{max_points}) {
            $_->{max_points} = cache_max_points($_);
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

    my $idx = $self->{problems_idx} = {};
    $idx->{$_->{problem_id}} = $_ for @$problems;
}


sub get_results
{
    (my CATS::RankTable $self, my $cond_str, my $max_cached_req_id) = @_;
    my @conditions = ();
    my @params = ();
    unless($is_jury) {
        if ($self->{frozen}) {
            if ($is_team) {
                push @conditions, '(R.submit_time < C.freeze_date OR R.account_id = ?)';
                push @params, $uid;
            }
            else {
                push @conditions, 'R.submit_time < C.freeze_date';
            }
        }
        if ($is_team && !$is_jury && $virtual_diff_time) {
            push @conditions, "(R.submit_time - CA.diff_time < CURRENT_TIMESTAMP - $virtual_diff_time)";
        }
        push @conditions, '(C.show_all_results = 1 OR R.account_id = ?)';
        push @params, $uid || 0;
    }

    $cond_str .= join '', map " AND $_", @conditions;

    $dbh->selectall_arrayref(qq~
        SELECT
            R.id, R.state, R.problem_id, R.account_id, R.points, R.testsets,
            MAXVALUE((R.submit_time - C.start_date - CA.diff_time) * 1440, 0) AS time_elapsed
        FROM reqs R, contests C, contest_accounts CA, contest_problems CP
        WHERE
            CA.contest_id = C.id AND CA.account_id = R.account_id AND R.contest_id = C.id AND
            CP.problem_id = R.problem_id AND CP.contest_id = C.id AND
            CA.is_hidden = 0 AND CP.status < ? AND R.state >= ? AND R.id > ? AND
            C.id IN ($self->{contest_list})$cond_str
        ORDER BY R.id~, { Slice => {} },
        $cats::problem_st_hidden, $cats::request_processed, $max_cached_req_id, @params
    );
}


sub get_partial_points
{
    my ($req_row, $test_max_points) = @_;
    my $p = ($req_row->{checker_comment} // '') =~ /^(\d+)/ ? min($1, $test_max_points || $1) : 0;
}


sub cache_req_points
{
    my ($req, $problem) = @_;
    my $test_points = $dbh->selectall_arrayref(qq~
        SELECT RD.result, RD.checker_comment, T.points, T.rank
            FROM reqs R
            INNER JOIN req_details RD ON RD.req_id = R.id
            INNER JOIN tests T ON RD.test_rank = T.rank AND T.problem_id = R.problem_id
        WHERE R.id = ?~, { Slice => {} },
        $req->{id}
    );

    my $test_testsets = $req->{testsets} ? get_test_testsets($problem, $req->{testsets}) : {};
    my %used_testsets;
    my $total = sum map {
        my $t = $test_testsets->{$_->{rank}};
        $_->{result} != $cats::st_accepted ? 0 :
        # Scoring groups have priority over partial checkers,
        # although they should not be used together.
        $t ? (++$used_testsets{$t->{name}} == $t->{test_count} ? $t->{points} : 0) :
        $problem->{partial_checker} ? get_partial_points($_, $_->{points}) :
        max($_->{points} || 0, 0)
    } @$test_points;

    # To reduce chance of deadlock, commit every change separately, even if it is slower.
    $dbh->do(q~
        UPDATE reqs SET points = ? WHERE id = ? AND points IS NULL~, undef, $total, $req->{id});
    $dbh->commit;
    $total;
}


sub get_contest_list_param
{
    (my CATS::RankTable $self) = @_;
    my $clist = url_param('clist') || $cid;
    # sanitize
    $self->{contest_list} =
        join(',', sort { $a <=> $b } grep { $_ > 0 }
            map { sprintf '%d', $_ } split ',', $clist) || $cid;
}


sub common_prefix
{
    my ($pa, $pb) = @_;
    my $i = 0;
    ++$i while $i < @$pa && $i < @$pb && $pa->[$i] eq $pb->[$i];
    [ @$pa[0 .. $i - 1] ];
}


sub get_contests_info
{
    (my CATS::RankTable $self, my $uid) = @_;
    $uid ||= 0;

    $self->{frozen} = $self->{not_started} = $self->{has_practice} = $self->{show_points} = 0;
    my $sth = $dbh->prepare(qq~
        SELECT C.title,
          CAST(CURRENT_TIMESTAMP - C.freeze_date AS DOUBLE PRECISION),
          CAST(CURRENT_TIMESTAMP - C.defreeze_date AS DOUBLE PRECISION),
          CAST(CURRENT_TIMESTAMP - C.start_date AS DOUBLE PRECISION),
          (SELECT COUNT(*) FROM contest_accounts WHERE contest_id = C.id AND account_id = ?),
          C.rules, C.ctype, C.show_all_results
        FROM contests C
        WHERE id IN ($self->{contest_list})~
    );
    $sth->execute($uid);

    my $common_title;
    my $contest_count = 0;
    $self->{show_all_results} = 1;
    while (my (
        $title, $since_freeze, $since_defreeze, $since_start, $registered,
        $rules, $ctype, $show_all_results) =
            $sth->fetchrow_array)
    {
        ++$contest_count;
        $self->{frozen} ||= $since_freeze > 0 && $since_defreeze < 0;
        $self->{not_started} ||= $since_start < 0 && !$is_jury;
        $self->{has_practice} ||= ($ctype || 0);
        $self->{show_points} ||= $rules;
        $self->{show_all_results} &&= $show_all_results;
        my @title_words = grep $_, split /\s+|_/, Encode::decode_utf8($title);
        $common_title = $common_title ? common_prefix($common_title, \@title_words) : \@title_words;
    }
    $self->{title} =
         (join(' ', @$common_title) || 'Contests') .
         ($contest_count > 1 ? " ($contest_count)" : '');
}


sub parse_params
{
    (my CATS::RankTable $self) = @_;

    $self->{hide_ooc} = url_param('hide_ooc') || '0';
    $self->{hide_ooc} =~ /^[01]$/
        or $self->{hide_ooc} = 0;

    $self->{hide_virtual} = url_param('hide_virtual') || '0';
    $self->{hide_virtual} =~ /^[01]$/
        or $self->{hide_virtual} = (!$is_virtual && !$is_jury || !$is_team);

    $self->get_contest_list_param;
    $self->get_contests_info($uid);
    # Summary results must not include practice contest.
    !$self->{has_practice} || $self->{contest_list} eq $cid or return;
    $self->{show_points} = url_param('points') if defined url_param('points');
    $self->{use_cache} = url_param('cache');
    # Cache external links by default.
    $self->{use_cache} = 1 if !defined $self->{use_cache} && !defined $uid;
    $self->{use_cache} = 0 unless $self->{show_all_results};
    $self->{filter} = param('filter');
    $self->{show_prizes} = url_param('show_prizes');
}


sub prepare_ranks
{
    (my CATS::RankTable $self, my $teams) = @_;

    my @rank = values %$teams;

    if ($self->{filter}) {
        my $negate = $self->{filter} =~ /^\!(.*)$/;
        my $filter = Encode::decode_utf8($negate ? $1 : $self->{filter});
        my $filter_fields = sub { join '', map $_ || '', @{$_[0]}{qw(tag team_name city)} };
        @rank = grep $negate == (index($filter_fields->($_), $filter) < 0), @rank;
    }

    my $sort_criteria = $self->{show_points} ?
        sub {
            $b->{total_points} <=> $a->{total_points} ||
            $b->{total_runs} <=> $a->{total_runs}
        }:
        sub {
            $b->{total_solved} <=> $a->{total_solved} ||
            $a->{total_time} <=> $b->{total_time} ||
            $b->{total_runs} <=> $a->{total_runs}
        };
    @rank = sort $sort_criteria @rank;

    my ($row_num, $same_place_count, $row_color) = (1, 0, 0);
    my %prev = ('time' => 1000000, solved => -1, points => -1);

    my $prizes = [];
    if ($self->{show_prizes}) {
        $prizes = $dbh->selectall_arrayref(q~
            SELECT p.rank, p.name FROM prizes p INNER JOIN contest_groups cg ON p.cg_id = cg.id
            WHERE cg.clist = ? ORDER BY p.rank~, { Slice => {} },
            $self->{contest_list});
    }
    my $ooc_count = 0;

    for my $team (@rank)
    {
        my @columns = ();

        for (@{$self->{problems}})
        {
            my $p = $team->{problems}->{$_->{problem_id}};

            my $c = $p->{solved} ? '+' . ($p->{runs} - 1 || '') : -$p->{runs} || '.';

            push @columns, {
                td => $c, 'time' => ($p->{time_hm} || ''),
                points => (defined $p->{points} ? $p->{points} : '.')
            };
        }

        $row_color = 1 - $row_color
            if $self->{show_points} ? $row_num % 5 == 1 : $prev{solved} > $team->{total_solved};
        if ($self->{show_points} ?
                $prev{points} > $team->{total_points} :
                $prev{solved} > $team->{total_solved} || $prev{'time'} < $team->{total_time})
        {
            $same_place_count = 1;
        }
        else
        {
            $same_place_count++;
        }

        $prev{$_} = $team->{"total_$_"} for keys %prev;

        $team->{row_color} = $row_color;
        $team->{contestant_number} = $row_num++;
        $team->{place} = $row_num - $same_place_count;
        $team->{columns} = [ @columns ];
        $team->{show_points} = $self->{show_points};
        $team->{href_console} = url_f('console', uf => $team->{account_id});

        shift @$prizes while @$prizes && $prizes->[0]->{rank} < $team->{place} - $ooc_count;
        if ($team->{is_ooc} || $team->{is_virtual}) {
            ++$ooc_count;
        }
        elsif (@$prizes) {
            $team->{prize} = $prizes->[0]->{name};
        }
    }
    $self->{rank} = \@rank;
    ($row_num - 1, $row_color);
}


sub cache_file_name
{
    cats_dir() . './rank_cache/' . join ('#', @_, '');
}


sub remove_cache
{
    my ($contest_id) = @_;
    for my $virt (0, 1)
    {
        for my $ooc (0, 1)
        {
            unlink cache_file_name($contest_id, $virt, $ooc);
        }
    }
}


sub rank_table
{
    (my CATS::RankTable $self) = @_;

    my @p = ('rank_table', clist => $self->{contest_list}, cache => $self->{use_cache});
    $t->param(
        not_started => $self->{not_started} && !$is_jury,
        frozen => $self->{frozen},
        hide_ooc => !$self->{hide_ooc},
        hide_virtual => !$self->{hide_virtual},
        href_hide_ooc => url_f(@p, hide_ooc => 1, hide_virtual => $self->{hide_virtual}),
        href_show_ooc => url_f(@p, hide_ooc => 0, hide_virtual => $self->{hide_virtual}),
        href_hide_virtual => url_f(@p, hide_virtual => 1, hide_ooc => $self->{hide_ooc}),
        href_show_virtual => url_f(@p, hide_virtual => 0, hide_ooc => $self->{hide_ooc}),
        show_points => $self->{show_points},
    );
    #return if $not_started;

    $self->get_problems;
    my $virtual_cond = $self->{hide_virtual} ? ' AND (CA.is_virtual = 0 OR CA.is_virtual IS NULL)' : '';
    my $ooc_cond = $self->{hide_ooc} ? ' AND CA.is_ooc = 0' : '';

    my %init_problem = (runs => 0, time_consumed => 0, solved => 0, points => undef);
    my $select_teams = sub
    {
        my ($account_id) = @_;
        my $acc_cond = $account_id ? 'AND A.id = ?' : '';
        my $res = $dbh->selectall_hashref(qq~
            SELECT
                A.team_name, A.motto, A.country, A.city,
                MAX(CA.is_virtual) AS is_virtual, MAX(CA.is_ooc) AS is_ooc, MAX(CA.is_remote) AS is_remote,
                CA.account_id, CA.tag
            FROM accounts A INNER JOIN contest_accounts CA ON A.id = CA.account_id
            WHERE CA.contest_id IN ($self->{contest_list}) AND CA.is_hidden = 0
                $virtual_cond $ooc_cond $acc_cond
            GROUP BY CA.account_id, CA.tag, A.team_name, A.motto, A.country, A.city~, 'account_id', { Slice => {} },
            ($account_id || ())
        );

        for my $team (values %$res)
        {
            # Since virtual team is always ooc, do not output extra string.
            $team->{is_ooc} = 0 if $team->{is_virtual};
            $team->{$_} = 0 for qw(total_solved total_runs total_time total_points);
            ($team->{country}, $team->{flag}) = get_flag($team->{country});
            $team->{$_} = Encode::decode_utf8($team->{$_}) for qw(team_name city tag);
            $team->{problems} = { map { $_->{problem_id} => { %init_problem } } @{$self->{problems}} };
        }

        $res;
    };

    my $cache_file = cache_file_name(@$self{qw(contest_list hide_ooc hide_virtual)});

    my ($teams, $problem_stats, $max_cached_req_id) = ({}, {}, 0);
    if ($self->{use_cache} && !$is_virtual &&  -f $cache_file &&
        (my $cache = Storable::lock_retrieve($cache_file)))
    {
        ($teams, $problem_stats, $max_cached_req_id) = @{$cache}{qw(t p r)};
        # A problem was added after last cache refresh -- initialize it.
        for my $p (map $_->{problem_id}, @{$self->{problems}})
        {
            next if $problem_stats->{$p};
            $problem_stats->{$p} = {};
            $_->{problems}->{$p} = { %init_problem } for values %$teams;
        }
    }
    else
    {
        $problem_stats->{$_} = {} for map $_->{problem_id}, @{$self->{problems}};
        $teams = $select_teams->($is_jury || $self->{show_all_results} ? undef : $uid || -1);
    }

    my $results = $self->get_results($virtual_cond . $ooc_cond, $max_cached_req_id);
    my $max_req_id = 0;
    for (@$results)
    {
        $max_req_id = $_->{id} if $_->{id} > $max_req_id;
        $_->{time_elapsed} ||= 0;
        next if $_->{state} == $cats::st_ignore_submit;
        my $t = $teams->{$_->{account_id}} || $select_teams->($_->{account_id});
        my $p = $t->{problems}->{$_->{problem_id}};
        if ($self->{show_points} && !defined $_->{points})
        {
            $_->{points} = cache_req_points($_, $self->{problems_idx}->{$_->{problem_id}});
        }
        next if $p->{solved} && !$self->{show_points};

        if ($_->{state} == $cats::st_accepted)
        {
            my $te = int($_->{time_elapsed} + 0.5);
            $p->{time_consumed} = $te + ($p->{runs} || 0) * $cats::penalty;
            $p->{time_hm} = sprintf('%d:%02d', int($te / 60), $te % 60);
            $p->{solved} = 1;
            $t->{total_time} += $p->{time_consumed};
            $t->{total_solved}++;
        }
        if ($_->{state} != $cats::st_security_violation) # && state != ignored ?
        {
            $p->{runs}++;
            $t->{total_runs}++;
            $p->{points} ||= 0;
            my $dp = ($_->{points} || 0) - $p->{points};
            $t->{total_points} += $dp;
            $p->{points} = $_->{points};
        }
    }

    if (!$self->{frozen} && !$is_virtual && @$results && !$self->{has_practice} && $self->{show_all_results})
    {
        Storable::lock_store({ t => $teams, p => $problem_stats, r => $max_req_id }, $cache_file);
    }

    my ($row_num, $row_color) = $self->prepare_ranks($teams);
    # Calculate stats.
    @$_{qw(total_runs total_accepted total_points)} = (0, 0, 0) for values %$problem_stats;
    for my $t (@{$self->{rank}})
    {
        for my $pid (keys %{$t->{problems}})
        {
            my $stat = $problem_stats->{$pid};
            my $tp = $t->{problems}->{$pid};
            $stat->{total_runs} += $tp->{runs};
            $stat->{total_accepted}++ if $tp->{solved};
            $stat->{total_points} += $tp->{points} || 0;
        }
    }

    my $pcount = @{$self->{problems}};
    $t->param(
        problem_colunm_width => (
            $pcount <= 6 ? 6 :
            $pcount <= 8 ? 5 :
            $pcount <= 10 ? 4 :
            $pcount <= 20 ? 3 : 2 ),
        problem_stats => [
            map {{
                %$_,
                percent_accepted => int(
                    $_->{total_accepted} /
                    ($_->{total_runs} || 1) * 100 + 0.5),
                average_points => sprintf('%.1f', $_->{total_points} / max($row_num, 1))
            }} map $problem_stats->{$_->{problem_id}}, @{$self->{problems}}
        ],
        problem_stats_color => 1 - $row_color,
        rank => $self->{rank},
        href_console => url_f('console'),
    );
    $t->param(cache_since => $max_req_id) if $is_jury;
}


1;
