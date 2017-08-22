package CATS::UI::Stats;

use strict;
use warnings;

use List::Util qw(max);

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $t);
use CATS::Messages qw(res_str);
use CATS::Output qw(init_template url_f);
use CATS::Problem::Utils;
use CATS::Verdicts;
use CATS::Web qw(param);

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

sub lists_to_strings { [ map { eq => join ',', @$_ }, @{$_[0]} ] }

sub compare_tests_frame {
    init_template('compare_tests.html.tt');
    $is_jury or return;
    my ($pid) = param('pid') or return;
    my ($pt) = $dbh->selectrow_array(q~
        SELECT title FROM problems WHERE id = ?~, undef,
        $pid);
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
        $pid, $cid) or return;

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
        $pid, $cid);

    my $h = {};
    $h->{$_->{r1}}->{$_->{r2}} = $_->{cnt} for @$c;
    my $size = max(keys %$totals) || 0;
    my $cm = [
        map {
            my $hr = $h->{$_} || {};
            {
                data => [ map {{ n => ($hr->{$_} || 0) }} 1..$size ],
                %{$totals->{$_} || {}},
                href_test_diff => url_f('test_diff', pid => $pid, test => $_),
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
        equiv_lists => lists_to_strings(greedy_cliques(@equiv_tests)),
        simple_tests => \@simple_tests,
        hard_tests => \@hard_tests,
    );
    CATS::Problem::Utils::problem_submenu('compare_tests', $pid);
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

sub similarity_frame {
    my ($p) = @_;
    init_template('similarity.html.tt');
    $is_jury && !$contest->is_practice or return;
    my $problems = $dbh->selectall_arrayref(q~
        SELECT P.id, P.title, CP.code
        FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE CP.contest_id = ? ORDER BY CP.code~, { Slice => {} },
        $cid);
    $p->{threshold} //= 50;
    $p->{self_diff} //= 0;
    $p->{all_contests} = 0 if !$is_root;
    $t->param(params => $p, problems => $problems, title_fuffix => res_str(545), );
    $p->{pid} or return;
    my $cond = {
        ($p->{all_contests} ? () : (contest_id => $cid)),
        ($p->{virtual} ? () : (is_virtual => 0)),
        ($p->{jury} ? () : (is_jury => 0)),
    };
    my ($where, @bind) = %$cond ? $sql->where($cond) : ('');
    # Manual join is faster.
    my $acc = $dbh->selectall_hashref(q~
        SELECT CA.account_id, CA.is_jury, CA.is_virtual, A.team_name, A.city
        FROM contest_accounts CA INNER JOIN accounts A ON CA.account_id = A.id~ . $where,
        'account_id', { Slice => {} },
        @bind);
    my $first_code = 100; # Ignore non-code DEs.
    my $reqs = $dbh->selectall_arrayref(q~
        SELECT R.id, R.account_id, S.src
        FROM reqs R INNER JOIN sources S ON S.req_id = R.id
        INNER JOIN default_de D ON D.id = S.de_id
        WHERE R.problem_id = ? AND D.code >= ?~ .
        ($p->{all_contests} ? '' : ' AND R.contest_id = ?'), { Slice => {} },
        $p->{pid}, $first_code, $p->{all_contests} ? () : ($cid));

    preprocess_source($_, $p->{collapse_idents}) for @$reqs;

    my @similar;
    my $by_account = {};
    for my $i (@$reqs) {
        my $ai = $acc->{$i->{account_id}} or next;
        for my $j (@$reqs) {
            my $aj = $acc->{$j->{account_id}} or next;
            next if
                $i->{id} >= $j->{id} ||
                (($i->{account_id} == $j->{account_id}) ^ $p->{self_diff});
            my $score = similarity_score($i->{hash}, $j->{hash});
            ($score * 100 > $p->{threshold}) ^ $p->{self_diff} or next;
            my $pair = {
                score => sprintf('%.1f%%', $score * 100), s => $score,
                n1 => [$ai], ($p->{self_diff} ? () : (n2 => [$aj])),
                href_diff => url_f('diff_runs', r1 => $i->{id}, r2 => $j->{id}),
                href_console => url_f('console', uf => $i->{account_id} . ',' . $j->{account_id}),
                t1 => $i->{account_id}, t2 => $j->{account_id},
            };
            if ($p->{group}) {
                for ($by_account->{$i->{account_id} . '#' . $j->{account_id}}) {
                    $_ = $pair if !defined $_ || (($_->{s} < $pair->{s}) ^ $p->{self_diff});
                }
            }
            else {
                push @similar, $pair;
            }
        }
    }
    @similar = values %$by_account if $p->{group};
    my $ids_to_teams = sub { [ map $acc->{$_}->{team_name}, @{$_[0]} ] };
    $t->param(
        similar => [ sort { ($b->{s} <=> $a->{s}) * ($p->{self_diff} ? -1 : 1) } @similar ],
        equiv_lists =>
            lists_to_strings [ map $ids_to_teams->($_), grep @$_ > 2, @{greedy_cliques @similar} ]
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
