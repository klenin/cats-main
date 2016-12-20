package CATS::ApiJudge;

use strict;
use warnings;

use JSON::XS;

use CATS::DB;
use CATS::Misc qw($sid);
use CATS::Web;

sub print_json {
    CATS::Web::content_type('application/json');
    CATS::Web::print(encode_json($_[0]));
    -1;
}

sub get_judge_id {
    my $id = $sid && $dbh->selectrow_array(q~
        SELECT J.id FROM judges J LEFT JOIN accounts A
        ON A.id = J.account_id WHERE A.sid = ?~, undef,
        $sid);
    print_json($id ? { id => $id } : { error => 'bad sid' });
}

sub update_state {
    $sid or print_json({ error => "bad sid"});

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
    $sid or print_json({ error => "bad sid"});

    my $db_de = $dbh->selectall_arrayref(q~
        SELECT id, code, description, memory_handicap FROM default_de~, { Slice => {} });

    print_json({ db_de => $db_de });
}

sub get_problem {
    $sid or print_json({ error => "bad sid"});
    my ($p) = @_;

    my $problem = $dbh->selectrow_hashref(q~
        SELECT
            id, title, upload_date, time_limit, memory_limit,
            input_file, output_file, std_checker, contest_id, formal_input,
            run_method
        FROM problems WHERE id = ?~, { Slice => {} }, $p->{pid});
    $problem->{run_method} //= $cats::rm_default;

    print_json({ problem => $problem });
}

sub get_problem_sources {
    $sid or print_json({ error => "bad sid"});
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
    $sid or print_json({ error => "bad sid"});
    my ($p) = @_;

    my $tests = $dbh->selectall_arrayref(q~
        SELECT generator_id, input_validator_id, rank, param, std_solution_id, in_file, out_file, gen_group
        FROM tests WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
        $p->{pid});

    print_json({ tests => $tests });
}

1;
