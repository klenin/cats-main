package CATS::RankTable;

use strict;
use warnings;

use List::Util qw(max min sum);

use CATS::Config qw(cats_dir);
use CATS::Constants;
use CATS::Contest::Utils;
use CATS::Countries;
use CATS::DB qw(:DEFAULT $db);
use CATS::Globals qw($cid $contest $is_jury $is_root $t $uid $user);
use CATS::Output qw(url_f url_f_cid);
use CATS::RankTable::Cache;
use CATS::RouteParser qw();
use CATS::Score;
use CATS::Testset;
use CATS::Time;

use fields qw(
    clist contests contest_list hide_ooc hide_virtual show_points frozen
    title has_practice not_started filter sites groups use_cache
    rank problems problems_idx show_all_results show_prizes has_competitive
    show_regions show_flags show_is_remote show_logins sort p notime nostats
    max_total_points
);

sub new {
    my ($self, $p) = @_;
    $self = fields::new($self) unless ref $self;
    $self->{p} = $p;
    $self->{clist} = [ @{$p->{clist}} ? sort { $a <=> $b } @{$p->{clist}} : $cid ];
    $self->{contest_list} = join ',', @{$self->{clist}};
    return $self;
}

sub get_problems {
    my ($self) = @_;
    my $problems = $self->{problems} = $dbh->selectall_arrayref(qq~
        SELECT
            CP.id AS cpid, CP.problem_id, CP.code, CP.contest_id,
            CP.testsets, CP.points_testsets, CP.color, C.start_date,
            CAST(CURRENT_TIMESTAMP - C.start_date AS DOUBLE PRECISION) AS since_start,
            CP.scaled_points, CP.round_points_to, CP.weight, CP.is_extra,
            CP.max_points, P.title, P.max_points AS max_points_def, P.run_method,
            C.local_only, C.penalty, C.penalty_except
        FROM
            contest_problems CP
            INNER JOIN contests C ON C.id = CP.contest_id
            INNER JOIN problems P ON P.id = CP.problem_id
        WHERE
            CP.contest_id IN ($self->{contest_list}) AND CP.status <= ?
        ORDER BY C.start_date, CP.code~, { Slice => {} },
        $cats::problem_st_disabled
    );

    my @contest_order;
    my $prev_cid = -1;
    my $need_commit = 0;
    $self->{max_total_points} = 0;
    for (@$problems) {
        my $c = $self->{contests}->{$_->{contest_id}};
        if ($_->{contest_id} != $prev_cid) {
            push @contest_order, $c;
            $prev_cid = $_->{contest_id};
        }
        $c->{count}++;
        # Optimization: do not link to problem text in local_only contests to avoid extra query.
        my $local_only = ($_->{since_start} < 0 || $_->{local_only}) && !$is_jury;
        $_->{problem_text} = $local_only ? '' : url_f('problem_text', cpid => $_->{cpid});
        if ($self->{show_points} && !$_->{max_points}) {
            $_->{max_points} = CATS::Score::cache_max_points($_);
            $need_commit = 1;
        }
        $_->{exclude_penalty} = {
            $cats::st_accepted => 1, map { $_ => 1 } split ',', $_->{penalty_except} // '' };
        $_->{scaled_points} += 0 if $_->{scaled_points};
        $_->{weight} = 1 * $_->{weight} if defined $_->{weight};
        $self->{max_total_points} += ($_->{scaled_points} || $_->{max_points} || 0) * ($_->{weight} // 1)
            unless $_->{is_extra};
        $self->{has_competitive} = 1 if $_->{run_method} == $cats::rm_competitive;
    }
    $dbh->commit if $need_commit;

    $t->param(
        problems => $problems,
        problem_column_width => min(max(int(600 / max(scalar @$problems, 1)) / 10, 1), 7),
        contests => $self->{contests},
        contest_order => \@contest_order,
        max_total_points => 0 + ($contest->{scaled_points} // $self->{max_total_points}),
    );

    my $idx = $self->{problems_idx} = {};
    $idx->{$_->{problem_id}} = $_ for @$problems;
}

sub get_results {
    my ($self, $cond_str, $max_cached_req_id) = @_;
    my (@conditions, @params);

    unless ($is_jury) {
        if ($self->{frozen}) {
            if ($uid) {
                push @conditions, '(R.submit_time < C.freeze_date OR R.account_id = ?)';
                push @params, $uid;
            }
            else {
                push @conditions, 'R.submit_time < C.freeze_date';
            }
        }
        if ($user->{is_participant} && $user->{diff_time}) {
            push @conditions, "(R.submit_time - $CATS::Time::diff_time_sql < CURRENT_TIMESTAMP - $user->{diff_time})";
        }
        push @conditions, '(C.show_all_results = 1 OR R.account_id = ?)';
        push @params, $uid || 0;
    }

    $cond_str .= join '', map " AND $_", @conditions;

    my $select_fields = qq~
        R.state, R.problem_id, R.points, R.testsets, R.contest_id,
        MAXVALUE(
            CAST(R.submit_time - $CATS::Time::contest_start_offset_sql AS DOUBLE PRECISION) * 1440,
            CAST(0 AS DOUBLE PRECISION)
        ) AS time_elapsed,
        CASE WHEN R.submit_time >= C.freeze_date THEN 1 ELSE 0 END AS is_frozen~;

    my $joins = q~
        INNER JOIN contests C ON C.id = R.contest_id
        INNER JOIN contest_problems CP ON CP.problem_id = R.problem_id AND CP.contest_id = R.contest_id
        INNER JOIN problems P ON P.id = R.problem_id
        LEFT JOIN contest_sites CS ON CS.contest_id = CA.contest_id AND CS.site_id = CA.site_id
        ~;

    # Disable index on C.id to improve speed on multi-contest rank tables.
    my $disable_index = @{$self->{clist}} > 1 && $max_cached_req_id ? ' + 0' : '';
    my $where = qq~
        CA.is_hidden = 0 AND CP.status < ? AND R.state >= ? AND R.id > ? AND
        C.id$disable_index IN ($self->{contest_list})$cond_str~;

    my $select_competitive_query = $self->{has_competitive} ? qq~
        UNION
            SELECT $select_fields, RO.id, R.id AS ref_id, RO.account_id, R.account_id AS ref_account_id
            FROM reqs R
            INNER JOIN req_groups RGE ON RGE.group_id = R.id
            INNER JOIN reqs RO ON RO.id = RGE.element_id
            INNER JOIN accounts AO ON AO.id = RO.account_id
            INNER JOIN contest_accounts CA ON CA.account_id = RO.account_id AND CA.contest_id = R.contest_id
            $joins
            WHERE
                EXISTS (SELECT * FROM req_groups RGP WHERE RGP.element_id = R.id) AND
                P.run_method = $cats::rm_competitive AND
                $where
    ~ : '';

    $dbh->selectall_arrayref(my $stmt = qq~
        SELECT * FROM (
            SELECT $select_fields, R.id, NULL AS ref_id, R.account_id, NULL as ref_account_id
            FROM reqs R
            INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
            $joins
            WHERE
                P.run_method <> $cats::rm_competitive AND
                $where
            $select_competitive_query
        ) AS x
        ORDER BY x.id~, { Slice => {} },
        ($cats::problem_st_hidden, $cats::request_processed, $max_cached_req_id, @params) x
            ($self->{has_competitive} ? 2 : 1));
}

sub _get_unprocessed {
    my ($self) = @_;
    $uid or return {};
    my ($stmt, @bind) = $sql->select('reqs', [ 'account_id', 'problem_id' ], {
        'contest_id' => $self->{clist},
        'state' => { '<', $cats::request_processed },
        ($is_jury ? () : ('account_id' => $uid)),
    }, 'id');
    # Avoid DoS for in case of mass-retest.
    my $u = $dbh->selectall_arrayref("$stmt $CATS::DB::db->{LIMIT} 1000", { Slice => {} }, @bind) || [];
    my $unprocessed = {};
    $unprocessed->{$_->{account_id}}->{$_->{problem_id}} = 1 for @$u;
    $unprocessed;
}

sub _get_first_unprocessed {
    my ($self) = @_;
    # Do not include AW submissions, manual state update clears cache anyway.
    $dbh->selectrow_array(_u $sql->select(
        'reqs R INNER JOIN jobs J ON J.req_id = R.id INNER JOIN jobs_queue JQ ON JQ.id = J.id',
        'MIN(R.id)', { 'R.contest_id' => $self->{clist} }
    ));
}

sub cache_req_points {
    my ($req, $problem) = @_;
    my $test_points = $dbh->selectall_arrayref(q~
        SELECT RD.result, RD.checker_comment, RD.points, T.points AS test_points, T.rank
            FROM reqs R
            INNER JOIN req_details RD ON RD.req_id = R.id
            INNER JOIN tests T ON RD.test_rank = T.rank AND T.problem_id = R.problem_id
        WHERE R.id = ?~, { Slice => {} },
        $req->{ref_id} || $req->{id}
    );

    my $test_testsets = $req->{testsets} ? CATS::Score::get_test_testsets($problem, $req->{testsets}) : {};
    my (%used_testsets, %accepted_tests, %accepted_deps);
    for (@$test_points) {
        $accepted_tests{$_->{rank}} = 1 if $_->{result} == $cats::st_accepted;
    }
    # Write zero points in case of zero tests run (e.g. CE) to mark reqest as cached.
    my $total = sum 0, map {
        my $t = $test_testsets->{$_->{rank}};
        $_->{test_points} //= 0;
        $_->{result} != $cats::st_accepted ? 0 :
        $t && $t->{depends_on} && !CATS::Score::dependencies_accepted(
            $problem->{all_testsets}, $t, \%accepted_tests, \%accepted_deps) ? 0 :
        # Scoring groups have priority over partial checkers,
        # although they should not be used together.
        $t && defined($t->{points}) ? (++$used_testsets{$t->{name}} == $t->{test_count} ? $t->{points} : 0) :
        !defined $_->{points} ? $_->{test_points} :
        min(max($_->{points}, 0), $_->{test_points});
    } @$test_points;

    # In case of school-style view of acm-style contest.
    $total ||= 1 if $req->{state} == $cats::st_accepted;
    eval {
        # To reduce chance of deadlock, commit every change separately, even if that is slower.
        $dbh->do(q~
            UPDATE reqs SET points = ? WHERE id = ? AND points IS DISTINCT FROM ?~, undef,
            $total, $req->{ref_id} || $req->{id}, $total);
        $dbh->commit;
        1;
    } or return $CATS::DB::db->catch_deadlock_error("cache_req_points $req->{id}");
    $total;
}

sub get_contests_info {
    my ($self, $uid) = @_;
    $uid ||= 0;
    $self->{frozen} = $self->{not_started} = $self->{has_practice} = $self->{show_points} = 0;
    my $sth = $dbh->prepare(qq~
        SELECT C.id, C.title, CAST(C.start_date AS DATE) AS start_date,
          CAST(CURRENT_TIMESTAMP - C.freeze_date AS DOUBLE PRECISION) AS since_freeze,
          CAST(CURRENT_TIMESTAMP - C.defreeze_date AS DOUBLE PRECISION) AS since_defreeze,
          CAST(CURRENT_TIMESTAMP - $CATS::Time::contest_start_offset_sql AS DOUBLE PRECISION) AS since_start,
          CA.is_jury, CA.id AS caid,
          C.is_hidden, C.rules, C.ctype, C.show_all_results, C.show_flags, C.req_selection, C.show_is_remote
        FROM contests C
        LEFT JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
        WHERE C.id IN ($self->{contest_list}) OR C.parent_id = ? AND (C.is_hidden = 0 OR CA.id IS NOT NULL)
        ORDER BY C.id~
    );
    $sth->execute($uid, $cid);

    my (@actual_contests, @names);
    $self->{show_all_results} = 1;
    while (my $c = $sth->fetchrow_hashref) {
        $self->{contests}->{$c->{id}} = $c;
        push @actual_contests, $c->{id};
        $self->{frozen} ||= $c->{since_freeze} >= 0 && $c->{since_defreeze} < 0;
        $self->{not_started} ||= $c->{since_start} < 0 && !$c->{is_jury};
        $self->{has_practice} ||= ($c->{ctype} || 0);
        $self->{show_points} ||= $c->{rules};
        $self->{show_all_results} &&= $c->{show_all_results};
        $self->{show_flags} ||= $c->{show_flags};
        $self->{show_is_remote} ||= $c->{show_is_remote};
        $c->{href_problems} = url_f_cid('problems', cid => $c->{id});
        push @names, $c->{title};
    }
    $self->{title} =
         (CATS::Contest::Utils::common_prefix(@names) || 'Contests') .
         (@actual_contests > 1 ? ' (' . @actual_contests . ')' : '');
    $self->{contest_list} = join ',', @actual_contests;
}

sub parse_params {
    my ($self, $p) = @_;

    $self->{hide_ooc} = $p->{hide_ooc} || 0;

    $self->{hide_virtual} = $p->{hide_virtual} //
        (!$user->{is_virtual} && !$is_jury || !$user->{is_participant}) || 0;

    $self->get_contests_info($uid);
    $self->{show_points} = $p->{points} if defined $p->{points};
    $self->{use_cache} = $p->{cache};
    # Cache external links by default.
    $self->{use_cache} = 1 if !defined $self->{use_cache} && !defined $uid;
    $self->{use_cache} = 0 unless $self->{show_all_results};
    $self->{filter} = $p->{filter};
    $self->{groups} = $p->{groups};
    $self->{sites} = $p->{sites};
    $self->{show_prizes} = $p->{show_prizes};
    $self->{show_regions} = $p->{show_regions};
    $self->{show_logins} = $p->{show_logins};
    $self->{show_flags} = $p->{show_flags} if defined $p->{show_flags};
    $self->{show_is_remote} = 0;
    $self->{sort} = $p->{sort} // '';
    $self->{notime} = $p->{notime};
    $self->{nostats} = $p->{nostats};
}

sub prepare_ranks {
    my ($self, $teams, $unprocessed) = @_;

    my @rank = values %$teams;

    if ($self->{filter}) {
        my $negate = $self->{filter} =~ /^\!(.*)$/;
        my $filter = $negate ? $1 : $self->{filter};
        my $filter_fields = sub { join '', map $_ || '', @{$_[0]}{qw(tag team_name city affiliation_year)} };
        @rank = grep $negate == (index($filter_fields->($_), $filter) < 0), @rank;
    }

    if (@{$self->{sites}}) {
        my %sites = map { $_ => 1 } @{$self->{sites}};
        @rank = grep $sites{$_->{site_id} // 0}, @rank;
    }

    if (@{$self->{groups}}) {
        my $accounts_by_groups = $dbh->selectcol_arrayref(_u $sql->select('acc_group_accounts',
            'account_id', { acc_group_id => $self->{groups} }));
        my %h;
        @h{@$accounts_by_groups} = undef;
        @rank = grep exists $h{$_->{account_id}}, @rank;
    }

    my $sort_criteria = $self->{sort} eq 'name' ?
        sub {
            $a->{team_name} cmp $b->{team_name}
        } :
    $self->{show_points} ?
        sub {
            $b->{total_points} <=> $a->{total_points} ||
            $b->{total_runs} <=> $a->{total_runs}
        } :
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
            SELECT P.rank, P.name
            FROM prizes P INNER JOIN contest_groups CG ON P.cg_id = CG.id
            WHERE CG.clist = ? ORDER BY P.rank~, { Slice => {} },
            $self->{contest_list});
    }
    my $ooc_count = 0;

    for my $team (@rank) {
        my @columns = ();

        my $u = $unprocessed->{$team->{account_id}};
        for (@{$self->{problems}}) {
            my $p = $team->{problems}->{$_->{problem_id}};

            my $c =
                $p->{solved} ? '+' . ($p->{runs} - 1 || '') :
                $u->{$_->{problem_id}} ? '?' . ($p->{runs} || '') :
                -$p->{runs} || '.';

            push @columns, {
                td => $c, 'time' => ($p->{time_hm} || ''),
                points => (defined $p->{points} ? $p->{points} : '.'),
            };
        }

        $row_color = 1 - $row_color
            if $self->{show_points} ? $row_num % 5 == 1 : $prev{solved} > $team->{total_solved};
        my $place_changed = $self->{show_points} ?
            $prev{points} > $team->{total_points} :
            $prev{solved} > $team->{total_solved} || $prev{'time'} < $team->{total_time};
        if ($place_changed) {
            $same_place_count = 1;
        }
        else {
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

sub same_or_default { @_ > 1 ? -1 : $_[0]; }

sub search_clist {
    my ($self) = @_;
    join ',', map "contest_id=$_", split ',', $self->{contest_list};
}

my %init_problem = (runs => 0, penalty_runs => 0, time_consumed => 0, solved => 0, points => undef);

sub _virtual_ooc_cond {
    ($_[0]->{hide_virtual} ? ' AND (CA.is_virtual = 0 OR CA.is_virtual IS NULL)' : '') .
    ($_[0]->{hide_ooc} ? ' AND CA.is_ooc = 0' : '')
}

sub _select_teams {
    my ($self, $account_id) = @_;
    my $virtual_ooc_cond = $self->_virtual_ooc_cond;
    my $acc_cond = $account_id ? 'AND A.id = ?' : '';
    my $account_fields = q~A.login, A.team_name, A.motto, A.country, A.city, A.affiliation_year~;
    my $res = $dbh->selectall_hashref(qq~
        SELECT
            $account_fields,
            MAX(CA.is_virtual) AS is_virtual, MAX(CA.is_ooc) AS is_ooc, MAX(CA.is_remote) AS is_remote,
            CA.account_id, CA.tag, CA.site_id,
            LIST((SELECT LIST(CAA.award_id, ' ')
                FROM contest_account_awards CAA
                INNER JOIN awards AW ON AW.id = CAA.award_id
                WHERE CAA.ca_id = CA.id AND AW.is_public = 1 $db->{LIMIT} 5), ' ') AS awards
        FROM accounts A INNER JOIN contest_accounts CA ON A.id = CA.account_id
        WHERE CA.contest_id IN ($self->{contest_list}) AND CA.is_hidden = 0
            $virtual_ooc_cond $acc_cond
        GROUP BY CA.account_id, CA.tag, CA.site_id, $account_fields~, 'account_id', { Slice => {} },
        ($account_id || ())
    );
    my $awards = $dbh->selectall_hashref(qq~
        SELECT AW.id, AW.name, AW.color FROM awards AW
        WHERE AW.contest_id IN ($self->{contest_list}) AND AW.is_public = 1~,
        'id', { Slice => {} });

    for my $team (values %$res) {
        # Since virtual team is always ooc, do not output extra string.
        $team->{is_ooc} = 0 if $team->{is_virtual};
        $team->{is_remote} = 0 if !$self->{show_is_remote};
        $team->{$_} = 0 for qw(total_solved total_runs total_time total_points);
        ($team->{country}, $team->{flag}) = CATS::Countries::get_flag($team->{country});
        $team->{problems} = { map { $_->{problem_id} => { %init_problem } } @{$self->{problems}} };
        $team->{awards} = [ grep $_, map $awards->{0 + $_}, split /\s+/, $team->{awards} // '' ];
    }

    $res;
}

sub _empty_cache {
    my ($self) = @_;
    my $teams = $self->_select_teams($is_jury || $self->{show_all_results} ? undef : $uid || -1);
    my $problem_stats = { map { $_->{problem_id} => {} } @{$self->{problems}} };
    ($teams, $problem_stats, 0);
}

sub _read_cache {
    my ($self, $cache_file, $first_unprocessed) = @_;

    $self->{use_cache} && !$user->{is_virtual} &&  -f $cache_file &&
        (my $cache = eval { Storable::lock_retrieve($cache_file) })
        or return $self->_empty_cache;
    my ($teams, $problem_stats, $max_cached_req_id) = @{$cache}{qw(t p r)};
    !$first_unprocessed || $max_cached_req_id > $first_unprocessed
        or return $self->_empty_cache;
    # A problem was added after last cache refresh -- initialize it.
    for my $p (map $_->{problem_id}, @{$self->{problems}}) {
        next if $problem_stats->{$p};
        $problem_stats->{$p} = {};
        $_->{problems}->{$p} = { %init_problem } for values %$teams;
    }
    ($teams, $problem_stats, $max_cached_req_id);
}

sub _process_single_run {
    my ($self, $r, $teams) = @_;
    $r->{time_elapsed} ||= 0;
    return if $r->{state} == $cats::st_ignore_submit;
    my $t = $teams->{$r->{account_id}} || $self->_select_teams($r->{account_id});
    my $ap = $t->{problems}->{$r->{problem_id}};
    my $problem = $self->{problems_idx}->{$r->{problem_id}};
    if ($self->{show_points} && !defined $r->{points}) {
        $r->{points} = cache_req_points($r, $problem);
    }
    return if $ap->{solved} && !$self->{show_points};

    $problem->{run_method} //= $cats::rm_default;
    if (
        $problem->{run_method} == $cats::rm_competitive &&
        (!defined $ap->{last_req_id} || $ap->{last_req_id} < $r->{id})
    ) {
        $t->{total_points} = $ap->{points} = 0;
        $ap->{last_req_id} = $r->{id};
    }

    if ($r->{state} == $cats::st_accepted) {
        my $te = int($r->{time_elapsed} + 0.5);
        $ap->{time_consumed} = $te + ($ap->{penalty_runs} || 0) * ($problem->{penalty} || $cats::penalty);
        $ap->{time_hm} = sprintf('%d:%02d', int($te / 60), $te % 60);
        $ap->{solved} = 1;
        $t->{total_time} += $ap->{time_consumed};
        $t->{total_solved}++;
    }
    $ap->{penalty_runs}++ unless $problem->{exclude_penalty}->{$r->{state}};
    $ap->{runs}++;
    $t->{total_runs}++;
    my $points = CATS::Score::scale_points($r->{points} || 0, $problem);
    if ($r->{state} != $cats::st_security_violation && $r->{state} != $cats::st_manually_rejected) {
        $ap->{points} ||= 0;

        if ($problem->{run_method} == $cats::rm_competitive) {
            $t->{total_points} += $points;
            $ap->{points} += $points;
        } else {
            my $dp = ($points || 0) - $ap->{points};
            # If req_selection is set to 'best', ignore negative point changes.
            if ($self->{contests}->{$r->{contest_id}}->{req_selection} == 0 || $dp > 0) {
                $t->{total_points} += $dp * ($problem->{weight} // 1);
                $ap->{points} = $points;
            }
        }
    }
}

sub rank_table {
    my ($self) = @_;

    my @pp = (clist => $self->{contest_list}, cache => $self->{use_cache});
    my $url = sub { url_f('rank_table', CATS::RouteParser::reconstruct($self->{p}, @pp, @_)) };
    $t->param(
        not_started => $self->{not_started} && !$is_jury,
        frozen => $self->{frozen},
        hide_ooc => !$self->{hide_ooc},
        hide_virtual => !$self->{hide_virtual},
        href_hide_ooc => $url->(hide_ooc => 1, hide_virtual => $self->{hide_virtual}),
        href_show_ooc => $url->(hide_ooc => 0, hide_virtual => $self->{hide_virtual}),
        href_hide_virtual => $url->(hide_virtual => 1, hide_ooc => $self->{hide_ooc}),
        href_show_virtual => $url->(hide_virtual => 0, hide_ooc => $self->{hide_ooc}),
        show_points => $self->{show_points},
        show_regions => $self->{show_regions},
        show_flags => $self->{show_flags},
        show_logins => $self->{show_logins},
        show_place => ($self->{sort} // '') ne 'name',
        req_selection => same_or_default(map $_->{req_selection}, values %{$self->{contests}}),
        notime => $self->{notime},
        nostats => $self->{nostats},
    );
    # Results must not include practice contest.
    !$self->{has_practice} && $self->{contest_list} or return;
    #return if $not_started;

    $self->get_problems;

    my $unprocessed = $self->_get_unprocessed;
    my $first_unprocessed = $self->_get_first_unprocessed;

    my $cache_file = CATS::RankTable::Cache::file_name(@$self{qw(contest_list hide_ooc hide_virtual)});

    my ($teams, $problem_stats, $max_cached_req_id) = $self->_read_cache($cache_file, $first_unprocessed);

    my $results = $self->get_results($self->_virtual_ooc_cond, $max_cached_req_id);
    my ($max_req_id, $cache_written) = (0, 0);

    my $write_cache = sub {
        !$self->{frozen} && !$user->{is_virtual} && @$results && $self->{show_all_results} && !$cache_written
            or return;
        Storable::lock_nstore({ t => $teams, p => $problem_stats, r => $max_req_id }, $cache_file);
        $cache_written  = 1;
    };

    for (@$results) {
        my $id = $_->{ref_id} || $_->{id};
        if ($id > $max_req_id) {
            $write_cache->() if $first_unprocessed && $id > $first_unprocessed;
            $max_req_id = $id;
        }
        $self->_process_single_run($_, $teams);
    }
    $write_cache->() if !$first_unprocessed || $max_req_id < $first_unprocessed;

    my $scale_params = {
        max_points => $self->{max_total_points},
        scaled_points => $contest->{scaled_points},
        round_points_to => $contest->{round_points_to},
    };
    # Scale after caching to preserve unscaled values, but before ranking since rounding may affect that.
    $_->{total_points} = CATS::Score::scale_points($_->{total_points}, $scale_params) for values %$teams;

    my ($row_num, $row_color) = $self->prepare_ranks($teams, $unprocessed);
    # Calculate stats.
    @$_{qw(total_runs total_accepted total_points)} = (0, 0, 0) for values %$problem_stats;
    for my $t (@{$self->{rank}}) {
        for my $pid (keys %{$t->{problems}}) {
            my $stat = $problem_stats->{$pid};
            my $tp = $t->{problems}->{$pid};
            $stat->{total_runs} += $tp->{runs};
            $stat->{total_accepted}++ if $tp->{solved};
            $stat->{total_points} += $tp->{points} || 0;
        }
    }
    CATS::Score::align_by_point($self->{rank}, 'total_points', "\x{2007}") # Unicode figure space.
        unless $self->{p}->{json};
    my $search_contest = $is_root ? $self->search_clist : '';
    my @href_submits_params = (i_value => -1, se => 'user_stats', show_results => 1, rows => 30);

    for my $pr (@{$self->{problems}}) {
        my $ps = $problem_stats->{$pr->{problem_id}};
        $ps->{percent_accepted} = int($ps->{total_accepted} / ($ps->{total_runs} || 1) * 100 + 0.5);
        $ps->{average_points} = sprintf '%.1f', $ps->{total_points} / max($row_num, 1);
        $ps->{href_submits} = url_f_cid 'console', @href_submits_params,
            (cid => $is_root ? $cid : $pr->{contest_id}),
            search => join(',', "problem_id=$pr->{problem_id}", $search_contest || ());
    }

    $t->param(
        problem_stats => [ map $problem_stats->{$_->{problem_id}}, @{$self->{problems}} ],
        problem_stats_color => 1 - $row_color,
        rank => $self->{rank},
        href_user_stats => url_f('user_stats'),
        href_submits => url_f('console', @href_submits_params, search => $search_contest),
        href_submits_problem => url_f_cid('console', @href_submits_params,
            (cid => $is_root ? $cid : 0),
            search => join(',', 'problem_id=0', $search_contest || ()),
        ),
    );
    $t->param(cache_since => $max_req_id) if $is_jury;
}

1;
