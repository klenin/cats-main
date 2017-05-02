package CATS::ApiJudge;

use strict;
use warnings;

use JSON::XS;

use CATS::Constants;
use CATS::DB;
use CATS::JudgeDB;
use CATS::Misc qw($sid);
use CATS::Testset;
use CATS::Web;

sub print_json {
    CATS::Web::content_type('application/json');
    CATS::Web::print(encode_json($_[0]));
    -1;
}

sub bad_judge {
    $sid && CATS::JudgeDB::get_judge_id($sid) ? 0 : print_json({ error => 'bad sid' });
}

sub get_judge_id {
    my $id = $sid && CATS::JudgeDB::get_judge_id($sid);
    print_json($id ? { id => $id } : { error => 'bad sid' });
}

sub get_DEs {
    bad_judge and return -1;

    print_json({ db_de => CATS::JudgeDB::get_DEs() });
}

sub get_problem {
    bad_judge and return -1;
    my ($p) = @_;

    print_json({ problem => CATS::JudgeDB::get_problem($p->{pid}) });
}

sub get_problem_sources {
    bad_judge and return -1;
    my ($p) = @_;

    print_json({ sources => CATS::JudgeDB::get_problem_sources($p->{pid}) });
}

sub get_problem_tests {
    bad_judge and return -1;
    my ($p) = @_;

    print_json({ tests => CATS::JudgeDB::get_problem_tests($p->{pid}) });
}

sub is_problem_uptodate {
    bad_judge and return -1;
    my ($p) = @_;

    print_json({ uptodate => CATS::JudgeDB::is_problem_uptodate($p->{pid}, $p->{date}) });
}

sub save_log_dump {
    bad_judge and return -1;
    my ($p) = @_;

    $p->{req_id} or return print_json({ error => 'No req_id' });
    CATS::JudgeDB::save_log_dump($p->{req_id}, $p->{dump});
    $dbh->commit;

    print_json({ ok => 1 });
}

sub set_request_state {
    bad_judge and return -1;
    my ($p) = @_;

    CATS::JudgeDB::set_request_state({
        jid         => CATS::JudgeDB::get_judge_id($sid),
        req_id      => $p->{req_id},
        state       => $p->{state},
        contest_id  => $p->{contest_id},
        problem_id  => $p->{problem_id},
        failed_test => $p->{failed_test},
    });

    print_json({ ok => 1 });
}

sub select_request {
    bad_judge and return -1;
    my ($p) = @_;
    $p->{supported_DEs} or return print_json({ error => 'bad request' });

    my $response = {};
    ($response->{was_pinged}, $response->{pin_mode}, my $jid, my $time_since_alive) = $dbh->selectrow_array(q~
        SELECT 1 - J.is_alive, J.pin_mode, J.id, CURRENT_TIMESTAMP - J.alive_date
        FROM judges J INNER JOIN accounts A ON J.account_id = A.id WHERE A.sid = ?~, undef,
        $sid);

    $response->{request} = CATS::JudgeDB::select_request({
        jid              => $jid,
        was_pinged       => $response->{was_pinged},
        pin_mode         => $response->{pin_mode},
        time_since_alive => $time_since_alive,
        supported_DEs    => $p->{supported_DEs},
    });

    print_json($response);
}

sub delete_req_details {
    bad_judge and return -1;
    my ($p) = @_;

    CATS::JudgeDB::delete_req_details($p->{req_id});

    print_json({ ok => 1 });
}

my @req_details_fields = qw(req_id test_rank result time_used memory_used disk_used checker_comment output output_size);

sub insert_req_details {
    bad_judge and return -1;
    my ($p) = @_;

    my $params = decode_json($p->{params});
    my %filtered_params = map { exists $params->{$_} ? ($_ => $params->{$_}) : () } @req_details_fields;
    CATS::JudgeDB::insert_req_details(%filtered_params);

    print_json({ ok => 1 });
}

sub get_testset {
    bad_judge and return -1;
    my ($p) = @_;

    my %testset = CATS::Testset::get_testset($dbh, $p->{req_id}, $p->{update});

    print_json({ testset => \%testset });
}

1;
