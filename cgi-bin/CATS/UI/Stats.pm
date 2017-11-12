package CATS::UI::Stats;

use strict;
use warnings;

use List::Util qw(max);

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(res_str);
use CATS::Output qw(init_template url_f);
use CATS::Problem::Utils;
use CATS::Verdicts;

sub greedy_cliques {
    my (@equiv_tests) = @_;
    my $eq_lists = [];
    while (@equiv_tests) {
        my $eq = [ @{$equiv_tests[0]}{qw(t1 t2)} ];
        shift @equiv_tests;
        my %cnt;
        for my $et (@equiv_tests) {
            $cnt{$et->{t2}}++ if grep $_ == $et->{t1}, @$eq;
        }
        my $neq = @$eq;
        for my $k (sort keys %cnt) {
            next unless $cnt{$k} == $neq;
            push @$eq, $k;
            my @new_et;
            for my $et (@equiv_tests) {
                push @new_et, $et unless $et->{t2} == $k && grep $_ == $et->{t1}, @$eq;
            }
            @equiv_tests = @new_et;
        }
        push @$eq_lists, $eq;
    }
    $eq_lists;
}

sub compare_tests_frame {
    my ($p) = @_;
    init_template('compare_tests.html.tt');
    $is_jury or return;
    my ($pt) = $dbh->selectrow_array(q~
        SELECT title FROM problems WHERE id = ?~, undef,
        $p->{pid});
    $pt or return;
    $t->param(problem_title => $pt);

    my $totals = $dbh->selectall_hashref(qq~
        SELECT
            SUM(CASE rd.result WHEN $cats::st_accepted THEN 1 ELSE 0 END) AS passed_count,
            SUM(CASE rd.result WHEN $cats::st_accepted THEN 0 ELSE 1 END) AS failed_count,
            rd.test_rank
        FROM reqs r
            INNER JOIN req_details rd ON rd.req_id = r.id
            INNER JOIN contest_accounts ca ON
                ca.contest_id = r.contest_id AND ca.account_id = r.account_id
        WHERE
            r.problem_id = ? AND r.contest_id = ? AND ca.is_jury = 0
        GROUP BY rd.test_rank~, 'test_rank', { Slice => {} },
        $p->{pid}, $cid) or return;

    my $c = $dbh->selectall_arrayref(qq~
        SELECT COUNT(*) AS cnt, rd1.test_rank AS r1, rd2.test_rank AS r2
            FROM reqs r
            INNER JOIN req_details rd1 ON rd1.req_id = r.id
            INNER JOIN req_details rd2 ON rd2.req_id = r.id
            INNER JOIN contest_accounts ca ON
                ca.contest_id = r.contest_id AND ca.account_id = r.account_id
            WHERE
                rd1.test_rank <> rd2.test_rank AND
                rd1.result = $cats::st_accepted AND
                rd2.result <> $cats::st_accepted AND
                r.problem_id = ? AND r.contest_id = ? AND ca.is_jury = 0
            GROUP BY rd1.test_rank, rd2.test_rank~, { Slice => {} },
        $p->{pid}, $cid);

    my $h = {};
    $h->{$_->{r1}}->{$_->{r2}} = $_->{cnt} for @$c;
    my $size = max(keys %$totals) || 0;
    my $cm = [
        map {
            my $hr = $h->{$_} || {};
            {
                data => [ map {{ n => ($hr->{$_} || 0) }} 1..$size ],
                %{$totals->{$_} || {}},
                href_test_diff => url_f('test_diff', pid => $p->{pid}, test => $_),
            },
        } 1..$size
    ];

    my (@equiv_tests, @simple_tests, @hard_tests);
    for my $i (1..$size) {
        my ($too_simple, $too_hard) = (1, 1);
        for my $j (1..$size) {
            my $zij = !exists $h->{$i} || !exists $h->{$i}->{$j};
            my $zji = !exists $h->{$j} || !exists $h->{$j}->{$i};
            push @equiv_tests, { t1 => $i, t2 => $j } if $zij && $zji && $j > $i;
            $too_simple &&= $zji;
            $too_hard &&= $zij;
        }
        push @simple_tests, { t => $i } if $too_simple;
        push @hard_tests, { t => $i } if $too_hard;
    }

    $t->param(
        comparison_matrix => $cm,
        equiv_lists => greedy_cliques(@equiv_tests),
        simple_tests => \@simple_tests,
        hard_tests => \@hard_tests,
    );
    CATS::Problem::Utils::problem_submenu('compare_tests', $p->{pid});
}

sub preprocess_source {
    my $h = $_[0]->{hash} = {};
    my $collapse_indents = $_[1];
    for (split /\n/, $_[0]->{src}) {
        $_ = Encode::encode('WINDOWS-1251', $_);
        use bytes; # MD5 works with bytes, prevent upgrade to utf8
        s/\s+//g;
        if ($collapse_indents) {
            s/(\w+)/A/g;
        }
        else {
            s/(\w+)/uc($1)/eg;
        }
        s/\d+/1/g;
        $h->{Digest::MD5::md5_hex($_)} = 1;
    }
    return;
}

sub similarity_score {
    my ($i, $j) = @_;
    my $sim = 0;
    $sim++ for grep exists $j->{$_}, keys %$i;
    $sim++ for grep exists $i->{$_}, keys %$j;
    return $sim / (keys(%$i) + keys(%$j));
}

sub _get_reqs {
    my ($p) = @_;
    my $cond = {
        code => { '>=', 100 }, # Ignore non-code DEs.
        ($p->{all_contests} ? () : ('R.contest_id' => $cid)),
        ($p->{pid} ? (problem_id => $p->{pid}) : ()),
        ($p->{virtual} ? () : (is_virtual => 0)),
        ($p->{jury} ? () : (is_jury => 0)),
    };
    my ($where, @bind) = %$cond ? $sql->where($cond) : ('');

    # Manually join with accounts since it is faster.
    $dbh->selectall_arrayref(q~
        SELECT R.id, R.account_id, R.problem_id, R.contest_id, S.src
        FROM reqs R
        INNER JOIN contest_accounts CA ON CA.contest_id = R.contest_id AND CA.account_id = R.account_id
        INNER JOIN sources S ON S.req_id = R.id
        INNER JOIN default_de D ON D.id = S.de_id~ .
        $where, { Slice => {} },
        @bind);
}

sub similarity_frame {
    my ($p) = @_;
    my $lv = CATS::ListView->new(name => 'similarity', template => 'similarity.html.tt');
    $is_jury && !$contest->is_practice or return;

    my $s = $lv->settings;
    if ($lv->submitted) {
        $s->{$_} = $p->{$_} for qw(threshold self_diff all_contests pid accound_id collapse_idents group);
    }
    $s->{threshold} //= 50;
    $s->{self_diff} //= 0;
    delete $s->{all_contests} if !$is_root;

    my $problems = $dbh->selectall_arrayref(q~
        SELECT P.id, P.title, CP.code
        FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE CP.contest_id = ? ORDER BY CP.code~, { Slice => {} },
        $cid);

    my $users_sql = q~
        SELECT CA.account_id, CA.is_jury, CA.is_virtual, A.team_name, A.city
        FROM contest_accounts CA INNER JOIN accounts A ON CA.account_id = A.id ~;
    my $users = $dbh->selectall_arrayref(qq~
        $users_sql WHERE CA.contest_id = ? ORDER BY A.team_name~, { Slice => {} },
        $cid);

    my $users_idx = {};
    $users_idx->{$_->{account_id}} = $_ for @$users;

    $t->param(
        params => $s, problems => $problems, users => $users, users_idx => $users_idx,
        title_suffix => res_str(545),
    );
    $lv->submitted || $p->{cont} or return;
    $s->{pid} || $s->{account_id} && !$s->{all_contests} or return;

    my $reqs = _get_reqs($s);
    preprocess_source($_, $s->{collapse_idents}) for @$reqs;

    my %missing_users;
    my @similar;
    my $by_account = {};
    for my $i (@$reqs) {
        !$s->{account_id} || $i->{account_id} == $s->{account_id} or next;
        my $ai = $i->{account_id};
        for my $j (@$reqs) {
            my $aj = $j->{account_id};
            next if $i->{id} >= $j->{id} && !$s->{account_id};
            next if $s->{self_diff} ? $ai != $aj : $ai == $aj && $i->{contest_id} == $j->{contest_id};
            my $score = similarity_score($i->{hash}, $j->{hash});
            ($score * 100 > $s->{threshold}) ^ $s->{self_diff} or next;
            my $search =
                "account_id=$ai" . ($ai == $aj ? '' : ",account_id=$aj") .
                ",problem_id=$i->{problem_id}" .
                ($i->{problem_id} == $j->{problem_id} ? '' : ",problem_id=$j->{problem_id}");
            my $pair = {
                score => sprintf('%.1f', $score * 100), s => $score,
                href_diff => url_f('diff_runs', r1 => $i->{id}, r2 => $j->{id}),
                href_console => url_f('console',
                    se => 'user_stats', search => $search, i_value => -1, show_results => 1),
                t1 => $ai, t2 => $aj,
            };
            exists $users_idx->{$_} or $missing_users{$_} = 1 for $ai, $aj;
            if ($s->{group}) {
                for ($by_account->{"$ai#$aj"}) {
                    $_ = $pair if !defined $_ || (($_->{s} < $pair->{s}) ^ $s->{self_diff});
                }
            }
            else {
                push @similar, $pair;
            }
        }
    }
    if (%missing_users) {
        my ($cond, @bind) = $sql->where({ 'CA.account_id' => { -in => [ keys %missing_users ] } });
        my $more_users = $dbh->selectall_arrayref(_u "$users_sql$cond", @bind);
        $users_idx->{$_->{account_id}} = $_ for @$more_users;
    }
    @similar = values %$by_account if $s->{group};
    for (@similar) {
        $_->{name1} = $users_idx->{$_->{t1}}->{team_name};
        $_->{name2} = $users_idx->{$_->{t2}}->{team_name};
    }

    $lv->define_columns(url_f('similarity'), 0, 0, [
        { caption => res_str(664), width => '5%', order_by => 'score', numeric => 1 },
        { caption => res_str(608) . ' 1', width => '30%', order_by => 'name1' },
        { caption => res_str(608) . ' 2', width => '30%', order_by => 'name2' },
        { caption => res_str(665), width => '5%', order_by => 'link' },
    ]);

    my $fetch_record = sub {
        my $pair = shift @{$_[0]} or return ();
        %$pair;
    };

    $lv->attach(
        url_f('similarity'), $fetch_record,
        $lv->sort_in_memory(\@similar), { page_params => { cont => 1 } });

    $t->param(
        equiv_lists => [ grep @$_ > 2, @{greedy_cliques @similar} ],
        stats => {
            total => scalar @$reqs,
            similar => scalar @similar,
            missing => scalar keys %missing_users,
        },
    );
}

sub test_diff_frame {
    my ($p) = @_;
    init_template('test_diff.html.tt');
    $is_jury && $p->{pid} && $p->{test} or return;
    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.id, P.title FROM problems P WHERE id = ?~, { Slice => {} },
        $p->{pid}) or return;
    my $reqs = $dbh->selectall_arrayref(q~
        SELECT R.id, R.account_id, R.problem_id, R.state, R.failed_test, A.team_name
        FROM reqs r
        INNER JOIN accounts A ON A.id = R.account_id
        WHERE R.contest_id = ? AND R.problem_id = ? AND
            (R.state = ? OR R.state > ? AND R.failed_test >= ?)
        ORDER BY A.team_name, R.account_id, R.id~, { Slice => {} },
        $cid, $p->{pid}, $cats::st_accepted, $cats::st_accepted, $p->{test});
    my ($prev, @fr);
    for my $r (@$reqs) {
        $r->{verdict} = $CATS::Verdicts::state_to_name->{$r->{state}};
        undef $prev if $prev && $prev->{account_id} != $r->{account_id};
        $prev or next;
        $prev->{state} > $cats::st_accepted && $prev->{failed_test} == $p->{test} &&
        ($r->{state} == $cats::st_accepted  || $r->{failed_test} > $p->{test})
            or next;
        push @fr, $r;
        $r->{href_run_details} = url_f('run_details', rid => join ',', $prev->{id}, $r->{id});
        $r->{href_diff_runs} = url_f('diff_runs', r1 => $prev->{id}, r2 => $r->{id});
    } continue {
        $r->{prev} = $prev;
        $prev = $r;
    }
    $t->param(reqs => \@fr, problem => $problem, test => $p->{test});
    CATS::UI::ProblemDetails::problem_submenu('compare_tests', $p->{pid});
}

1;
