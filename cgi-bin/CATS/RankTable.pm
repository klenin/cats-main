package CATS::RankTable;

use lib '..';
use strict;
use warnings;
use Encode;

use CGI qw(param url_param);
use List::Util qw(max);

use CATS::Constants;
use CATS::DB;
use CATS::Misc qw(
    $t $is_jury $is_team $virtual_diff_time $cid $uid url_f $is_virtual $contest cats_dir
    get_flag);

use fields qw(
    contest_list hide_ooc hide_virtual show_points frozen
    title has_practice not_started filter use_cache
    rank
);


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
    (my CATS::RankTable $self) = @_;
    # соответствующее требование: в одном чемпионате задача не должна дублироваться обеспечивается
    # при помощи UNIQUE(c,p)
    my $problems = $dbh->selectall_arrayref(qq~
        SELECT
            CP.id, CP.problem_id, CP.code, CP.contest_id, CATS_DATE(C.start_date) AS start_date,
            CATS_SYSDATE() - C.start_date AS since_start, C.local_only, P.max_points, P.title
        FROM
            contest_problems CP INNER JOIN contests C ON C.id = CP.contest_id
            INNER JOIN problems P ON P.id = CP.problem_id
        WHERE CP.contest_id IN ($self->{contest_list}) AND CP.status < ?
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
        if ($self->{show_points} && !$_->{max_points})
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


sub get_results
{
    (my CATS::RankTable $self, my $cond_str, my $max_cached_req_id) = @_;
    my @conditions = ();
    my @params = ();
    if ($self->{frozen} && !$is_jury)
    {
        if ($is_team)
        {
            push @conditions, '(R.submit_time < C.freeze_date OR R.account_id = ?)';
            push @params, $uid;
        }
        else
        {
            push @conditions, 'R.submit_time < C.freeze_date';
        }
    }
    if ($is_team && !$is_jury && $virtual_diff_time)
    {
        push @conditions, "(R.submit_time - CA.diff_time < CATS_SYSDATE() - $virtual_diff_time)";
    }

    $cond_str .= join '', map " AND $_", @conditions;

    $dbh->selectall_arrayref(qq~
        SELECT
            R.id, R.state, R.problem_id, R.account_id, R.points,
            ((R.submit_time - C.start_date - CA.diff_time) * 1440) AS time_elapsed
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


sub cache_req_points
{
    my ($req_id) = @_;
    my $points = $dbh->selectall_arrayref(qq~
        SELECT RD.result, T.points
            FROM reqs R
            INNER JOIN req_details RD ON RD.req_id = R.id
            INNER JOIN tests T ON RD.test_rank = T.rank AND T.problem_id = R.problem_id
        WHERE R.id = ?~, { Slice => {} },
        $req_id
    );

    my $total = 0;
    for (@$points)
    {
        $total += $_->{result} == $cats::st_accepted ? max($_->{points} || 0, 0) : 0;
    }

    $dbh->do(q~UPDATE reqs SET points = ? WHERE id = ?~, undef, $total, $req_id);
    $total;
}


sub get_contest_list_param
{
    (my CATS::RankTable $self) = @_;
    my $clist = url_param('clist') || $cid;
    # sanitize
    $self->{contest_list} =
        join(',', grep { $_ > 0 } map { sprintf '%d', $_ } split ',', $clist) || $cid;
}


sub get_contests_info
{
    (my CATS::RankTable $self, my $uid) = @_;
    $uid ||= 0;

    $self->{frozen} = $self->{not_started} = $self->{has_practice} = $self->{show_points} = 0;
    my $sth = $dbh->prepare(qq~
        SELECT C.title,
          CATS_SYSDATE() - C.freeze_date,
          CATS_SYSDATE() - C.defreeze_date,
          CATS_SYSDATE() - C.start_date,
          (SELECT COUNT(*) FROM contest_accounts WHERE contest_id = C.id AND account_id = ?),
          C.rules, C.ctype
        FROM contests C
        WHERE id IN ($self->{contest_list})~
    );
    $sth->execute($uid);
    
    my @common_title;
    while (my (
        $title, $since_freeze, $since_defreeze, $since_start, $registered, $rules, $ctype) =
        $sth->fetchrow_array)
    {
        $self->{frozen} ||= $since_freeze > 0 && $since_defreeze < 0;
        $self->{not_started} ||= $since_start < 0 && !$registered;
        $self->{has_practice} ||= ($ctype || 0);
        $self->{show_points} ||= $rules;
        my @title_words = split /\s+/, Encode::decode_utf8($title);
        if (@common_title)
        {
            my $i = 0;
            $i++ while $i < @common_title && $i < @title_words && $common_title[$i] eq $title_words[$i];
            @common_title = @common_title[0 .. $i - 1];
        }
        else
        {
            @common_title = @title_words;
        }
    }
    $self->{title} = join ' ', @common_title;
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
    # суммарные результаты не должны включать тренировочный турнир
    !$self->{has_practice} || $self->{contest_list} eq $cid or return;
    $self->{show_points} = url_param('points') if defined url_param('points');
    $self->{use_cache} = url_param('cache');
    # по умолчанию кешируем внешние ссылки
    $self->{use_cache} = 1 if !defined $self->{use_cache} && !defined $uid;
    $self->{filter} = param('filter');
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

    my @p_id = $self->get_problem_ids;
    my $virtual_cond = $self->{hide_virtual} ? ' AND (CA.is_virtual = 0 OR CA.is_virtual IS NULL)' : '';
    my $ooc_cond = $self->{hide_ooc} ? ' AND CA.is_ooc = 0' : '';

    my %init_problem = (runs => 0, time_consumed => 0, solved => 0, points => undef);
    my $select_teams = sub
    {
        my ($account_id) = @_;
        my $acc_cond = $account_id ? 'AND A.id = ?' : '';
        my $res = $dbh->selectall_hashref(qq~
            SELECT
                A.team_name, A.motto, A.country,
                MAX(CA.is_virtual) AS is_virtual, MAX(CA.is_ooc) AS is_ooc, MAX(CA.is_remote) AS is_remote,
                CA.account_id, CA.tag
            FROM accounts A, contest_accounts CA
            WHERE CA.contest_id IN ($self->{contest_list}) AND A.id = CA.account_id AND CA.is_hidden = 0
                $virtual_cond $ooc_cond $acc_cond
            GROUP BY CA.account_id, CA.tag, A.team_name, A.motto, A.country~, 'account_id', { Slice => {} },
            ($account_id || ())
        );

        for my $team (values %$res)
        {
            # поскольку виртуальный участник всегда ooc, не выводим лишнюю строчку
            $team->{is_ooc} = 0 if $team->{is_virtual};
            $team->{$_} = 0 for qw(total_solved total_runs total_time total_points);
            ($team->{country}, $team->{flag}) = get_flag($_->{country});
            $team->{problems} = { map { $_ => { %init_problem } } @p_id };
        }

        $res;
    };

    my $cache_file =
        cats_dir() . "./rank_cache/$self->{contest_list}#$self->{hide_ooc}#$self->{hide_virtual}#";

    my ($teams, $problems, $max_cached_req_id) = ({}, {}, 0);
    if ($self->{use_cache} && !$is_virtual &&  -f $cache_file &&
        (my $cache = Storable::lock_retrieve($cache_file)))
    {
        ($teams, $problems, $max_cached_req_id) = @{$cache}{qw(t p r)};
        # Если добавилась задача, проинициализируем её данные
        for my $p (@p_id)
        {
            next if $problems->{$p};
            $problems->{$p} = {};
            $_->{problems}->{$p} = { %init_problem } for values %$teams;
        }
    }
    else
    {
        $problems->{$_} = {} for @p_id;
        $teams = $select_teams->();
    }

    my $results = $self->get_results($virtual_cond . $ooc_cond, $max_cached_req_id);
    my ($need_commit, $max_req_id) = (0, 0);
    for (@$results)
    {
        $max_req_id = $_->{id} if $_->{id} > $max_req_id;
        $_->{time_elapsed} ||= 0;
        next if $_->{state} == $cats::st_ignore_submit;
        my $t = $teams->{$_->{account_id}} || $select_teams->($_->{account_id});
        my $p = $t->{problems}->{$_->{problem_id}};
        if ($self->{show_points} && !defined $_->{points})
        {
            $_->{points} = CATS::RankTable::cache_req_points($_->{id});
            $need_commit = 1;
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
        if ($_->{state} != $cats::st_security_violation) 
        {
            $p->{runs}++;
            $t->{total_runs}++;
            $p->{points} ||= 0;
            my $dp = ($_->{points} || 0) - $p->{points};
            $t->{total_points} += $dp;
            $p->{points} = $_->{points};
        }
    }

    $dbh->commit if $need_commit;
    if (!$self->{frozen} && !$is_virtual && @$results && !$self->{has_practice})
    {
        Storable::lock_store({ t => $teams, p => $problems, r => $max_req_id }, $cache_file);
    }

    my @rank = values %$teams;
    if ($self->{filter})
    {
        @rank = grep index(($_->{tag} || '') . $_->{team_name}, $self->{filter}) >= 0, @rank;
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

    for my $team (@rank)
    {
        my @columns = ();

        for (@p_id)
        {
            my $p = $team->{problems}->{$_};

            my $c = $p->{solved} ? '+' . ($p->{runs} - 1 || '') : -$p->{runs} || '.';

            push @columns, {
                td => $c, 'time' => ($p->{time_hm} || ''),
                points => (defined $p->{points} ? $p->{points} : '.')
            };
        }

        $row_color = 1 - $row_color
            if $self->{show_points} ? $row_num % 5 == 1 : $prev{solved} > $team->{total_solved};
        if ($self->{show_points} ?
                $prev{points} > $team->{total_points}:
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
    }

    # Расчёт статистики
    @$_{qw(total_runs total_accepted total_points)} = (0, 0, 0) for values %$problems;
    for my $t (@rank)
    {
        for my $pid (keys %{$t->{problems}})
        {
            my $stat = $problems->{$pid};
            my $tp = $t->{problems}->{$pid};
            $stat->{total_runs} += $tp->{runs};
            $stat->{total_accepted}++ if $tp->{solved};
            $stat->{total_points} += $tp->{points} || 0;
        }
    }

    $t->param(
        problem_colunm_width => (
            @p_id <= 6 ? 6 :
            @p_id <= 8 ? 5 :
            @p_id <= 10 ? 4 :
            @p_id <= 20 ? 3 : 2 ),
        problem_stats => [
            map {{
                %{$problems->{$_}},
                percent_accepted => int(
                    $problems->{$_}->{total_accepted} /
                    ($problems->{$_}->{total_runs} || 1) * 100 + 0.5),
                average_points => sprintf('%.1f', $problems->{$_}->{total_points} / $row_num)
            }} @p_id 
        ],
        problem_stats_color => 1 - $row_color,
        rank => [ @rank ]
    );
    $self->{rank} = \@rank;
}


1;
