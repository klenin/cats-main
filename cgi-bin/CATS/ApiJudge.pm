package CATS::ApiJudge;

use strict;
use warnings;

use JSON::XS;

use CATS::Constants;
use CATS::DB;
use CATS::Misc qw($sid);
use CATS::Testset;
use CATS::Web;

sub print_json {
    CATS::Web::content_type('application/json');
    CATS::Web::print(encode_json($_[0]));
    -1;
}

sub bad_judge {
    $sid && $dbh->selectrow_array(q~
        SELECT J.id FROM judges J LEFT JOIN accounts A
        ON A.id = J.account_id WHERE A.sid = ?~, undef,
        $sid) ? 0 : print_json({ error => 'bad sid' });
}

sub get_judge_id {
    my $id = $sid && $dbh->selectrow_array(q~
        SELECT J.id FROM judges J LEFT JOIN accounts A
        ON A.id = J.account_id WHERE A.sid = ?~, undef,
        $sid);
    print_json($id ? { id => $id } : { error => 'bad sid' });
}

sub update_state {
    bad_judge and return -1;

    my ($is_alive, $lock_counter, $jid, $time_since_alive) = $dbh->selectrow_array(q~
        SELECT J.is_alive, J.lock_counter, J.id, CURRENT_TIMESTAMP - J.alive_date
        FROM judges J INNER JOIN accounts A ON J.account_id = A.id WHERE A.sid = ?~, undef,
        $sid);

    $dbh->do(q~
        UPDATE judges SET is_alive = 1, alive_date = CURRENT_TIMESTAMP WHERE id = ?~, undef,
        $jid) if !$is_alive || $time_since_alive > $CATS::Config::judge_alive_interval / 24;
    $dbh->commit;

    print_json({ lock_counter => $lock_counter, is_alive => $is_alive });
}

sub get_DEs {
    bad_judge and return -1;

    my $db_de = $dbh->selectall_arrayref(q~
        SELECT id, code, description, memory_handicap FROM default_de~, { Slice => {} });

    print_json({ db_de => $db_de });
}

sub get_problem {
    bad_judge and return -1;
    my ($p) = @_;

    my $problem = $dbh->selectrow_hashref(q~
        SELECT
            id, title, upload_date, time_limit, memory_limit,
            input_file, output_file, std_checker, contest_id, formal_input,
            run_method
        FROM problems WHERE id = ?~, { Slice => {}, ib_timestampformat => '%d-%m-%Y %H:%M:%S' }, $p->{pid});
    $problem->{run_method} //= $cats::rm_default;

    print_json({ problem => $problem });
}

sub get_problem_sources {
    bad_judge and return -1;
    my ($p) = @_;

    my $problem_sources = $dbh->selectall_arrayref(q~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
        WHERE ps.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $p->{pid});

    my $imported = $dbh->selectall_arrayref(q~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
            INNER JOIN problem_sources_import psi ON ps.guid = psi.guid
        WHERE psi.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $p->{pid});
    $_->{is_imported} = 1 for @$imported;

    print_json({ sources => [ @$problem_sources, @$imported ] });
}

sub get_problem_tests {
    bad_judge and return -1;
    my ($p) = @_;

    my $tests = $dbh->selectall_arrayref(q~
        SELECT generator_id, input_validator_id, rank, param, std_solution_id, in_file, out_file, gen_group
        FROM tests WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
        $p->{pid});

    print_json({ tests => $tests });
}

sub is_problem_uptodate {
    bad_judge and return -1;
    my ($p) = @_;

    my $ok = scalar $dbh->selectrow_array(q~
        SELECT 1 FROM problems
        WHERE id = ? AND upload_date - 1.0000000000 / 24 / 60 / 60 <= ?~, undef,
        $p->{pid}, $p->{date});

    print_json({ uptodate => $ok });
}

sub save_log_dump {
    bad_judge and return -1;
    my ($p) = @_;

    warn $p->{dump};
    my $log_id = $dbh->selectrow_array(q~
        SELECT id FROM log_dumps WHERE req_id = ?~, undef, $p->{req_id});
    if (defined $log_id) {
        my $c = $dbh->prepare(q~UPDATE log_dumps SET dump = ? WHERE id = ?~);
        $c->bind_param(1, $p->{dump}, { ora_type => 113 });
        $c->bind_param(2, $log_id);
        $c->execute;
    }
    else {
        my $c = $dbh->prepare(q~INSERT INTO log_dumps (id, dump, req_id) VALUES (?, ?, ?)~);
        $c->bind_param(1, new_id);
        $c->bind_param(2, $p->{dump}, { ora_type => 113 });
        $c->bind_param(3, $p->{rid});
        $c->execute;
    }

    print_json({ ok => 1 });
}

sub set_request_state {
    bad_judge and return -1;
    my ($p) = @_;

    my ($jid) = $dbh->selectrow_array(q~
        SELECT J.id FROM judges J INNER JOIN accounts A ON J.account_id = A.id WHERE A.sid = ?~, undef,
        $sid);

    $dbh->do(qq~
        UPDATE reqs SET state = ?, failed_test = ?, result_time = CURRENT_TIMESTAMP
        WHERE id = ? AND judge_id = ?~, {},
        $p->{state}, $p->{failed_test}, $p->{req_id}, $jid);
    if ($p->{state} == $cats::st_unhandled_error && defined $p->{problem_id} && defined $p->{contest_id}) {
        $dbh->do(qq~
            UPDATE contest_problems SET status = ?
            WHERE problem_id = ? AND contest_id = ?~, {},
            $cats::problem_st_suspended, $p->{problem_id}, $p->{contest_id});
    }
    $dbh->commit;

    print_json({ ok => 1 });
}

sub select_request {
    bad_judge and return -1;
    my ($p) = @_;
    $p->{supported_DEs} or return print_json({ error => 'bad request' });

    my ($jid) = $dbh->selectrow_array(q~
        SELECT J.id FROM judges J INNER JOIN accounts A ON J.account_id = A.id WHERE A.sid = ?~, undef,
        $sid);
    my $sth = $dbh->prepare_cached(qq~
        SELECT
            R.id, R.problem_id, R.contest_id, R.state, CA.is_jury, C.run_all_tests,
            CP.status, S.fname, S.src, S.de_id
        FROM reqs R
        INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
        INNER JOIN contests C ON C.id = R.contest_id
        INNER JOIN sources S ON S.req_id = R.id
        INNER JOIN default_de D ON D.id = S.de_id
        LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
        WHERE R.state = ? AND
            (CP.status <= ? OR CA.is_jury = 1) AND
            D.code IN ($p->{supported_DEs}) AND (judge_id IS NULL OR judge_id = ?)
        ROWS 1~);
    my $req = $dbh->selectrow_hashref(
        $sth, { Slice => {} }, $cats::st_not_processed, $cats::problem_st_ready, $jid)
        or return print_json({ request => undef });

    $dbh->do(q~
        UPDATE reqs SET state = ?, judge_id = ? WHERE id = ?~, {},
        $cats::st_install_processing, $jid, $req->{id});
    $dbh->commit;

    print_json({ request => $req });
}

sub delete_req_details {
    bad_judge and return -1;
    my ($p) = @_;

    $dbh->do(q~DELETE FROM req_details WHERE req_id = ?~, undef, $p->{req_id});
    $dbh->commit;

    print_json({ ok => 1 });
}

my @req_details_fields = qw(req_id test_rank result time_used memory_used disk_used checker_comment);

sub insert_req_details {
    bad_judge and return -1;
    my ($p) = @_;

    my $params = decode_json($p->{params});
    my %filtered_params = map { exists $params->{$_} ? ($_ => $params->{$_}) : () } @req_details_fields;

    $dbh->do(
        sprintf(
            q~INSERT INTO req_details (%s) VALUES (%s)~,
            join(', ', keys %filtered_params), join(', ', ('?') x keys %filtered_params)
        ),
        undef, values %filtered_params
    );
    $dbh->commit;

    print_json({ ok => 1 });
}

sub get_testset {
    bad_judge and return -1;
    my ($p) = @_;

    my %testset = CATS::Testset::get_testset($p->{req_id}, $p->{update});

    print_json({ testset => \%testset });
}

1;
