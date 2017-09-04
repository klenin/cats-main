package CATS::ApiJudge;

use strict;
use warnings;

use JSON::XS;
use Math::BigInt;

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($sid);
use CATS::JudgeDB;
use CATS::Testset;
use CATS::Web;

# DE bitmap cache may return bigints.
sub Math::BigInt::TO_JSON { $_[0]->bstr }

sub print_json {
    CATS::Web::content_type('application/json');
    CATS::Web::print(JSON::XS->new->utf8->convert_blessed(1)->encode($_[0])); 1;
    -1;
}

my $bad_sid = { error => 'bad sid' };
my $stolen = { error => 'stolen' };

sub bad_judge {
    $sid && CATS::JudgeDB::get_judge_id($sid) ? 0 : print_json($bad_sid);
}

sub get_judge_id {
    my $id = $sid && CATS::JudgeDB::get_judge_id($sid);
    print_json($id ? { id => $id } : $bad_sid);
}

sub get_DEs {
    bad_judge and return -1;

    print_json(CATS::JudgeDB::get_DEs(@_));
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
    my ($p) = @_;
    my $judge_id = $sid && CATS::JudgeDB::get_judge_id($sid)
        or return print_json($bad_sid);

    $p->{req_id} or return print_json({ error => 'No req_id' });

    my $dump = CATS::Web::has_upload('dump') ? CATS::Web::upload_source('dump') : $p->{dump};
    CATS::JudgeDB::save_log_dump($p->{req_id}, $dump, $judge_id);
    $dbh->commit;

    print_json({ ok => 1 });
}

sub set_request_state {
    my ($p) = @_;
    my $judge_id = $sid && CATS::JudgeDB::get_judge_id($sid)
        or return print_json($bad_sid);

    CATS::JudgeDB::set_request_state({
        jid         => $judge_id,
        req_id      => $p->{req_id},
        state       => $p->{state},
        contest_id  => $p->{contest_id},
        problem_id  => $p->{problem_id},
        failed_test => $p->{failed_test},
    });

    print_json({ ok => 1 });
}

sub select_request {
    my ($p) = @_;

    $sid or return print_json($bad_sid);

    my @required_fields = ('de_version', map "de_bits$_", 1..$cats::de_req_bitfields_count);
    return print_json({ error => 'bad request' }) if grep !defined $p->{$_}, @required_fields;

    my $response = {};
    (
        $response->{was_pinged}, $response->{pin_mode}, my $jid, my $time_since_alive
    ) = $dbh->selectrow_array(q~
        SELECT 1 - J.is_alive, J.pin_mode, J.id, CURRENT_TIMESTAMP - J.alive_date
        FROM judges J INNER JOIN accounts A ON J.account_id = A.id WHERE A.sid = ?~, undef,
        $sid) or return print_json($bad_sid);

    $response->{request} = CATS::JudgeDB::select_request({
        jid              => $jid,
        was_pinged       => $response->{was_pinged},
        pin_mode         => $response->{pin_mode},
        time_since_alive => $time_since_alive,
        (map { $_ => $p->{$_} } @required_fields),
    });

    print_json($response->{request} && $response->{request}->{error} ?
        { error => $response->{request}->{error} } : $response);
}

sub delete_req_details {
    my ($p) = @_;

    my $judge_id = $sid && CATS::JudgeDB::get_judge_id($sid)
        or return print_json($bad_sid);

    CATS::JudgeDB::delete_req_details($p->{req_id}, $judge_id)
        or return print_json($stolen);

    print_json({ ok => 1 });
}

my @req_details_fields = qw(
    req_id test_rank result time_used memory_used disk_used checker_comment
    output output_size);

sub insert_req_details {
    my ($p) = @_;

    my $judge_id = $sid && CATS::JudgeDB::get_judge_id($sid)
        or return print_json($bad_sid);

    my $params = decode_json($p->{params});
    my %filtered_params =
        map { exists $params->{$_} ? ($_ => $params->{$_}) : () } @req_details_fields;
    CATS::JudgeDB::insert_req_details(%filtered_params, judge_id => $judge_id)
        or return print_json($stolen);

    print_json({ ok => 1 });
}

sub save_input_test_data {
    bad_judge and return -1;
    my ($p) = @_;

    CATS::JudgeDB::save_input_test_data(
        $p->{problem_id}, $p->{test_rank}, $p->{input}, $p->{input_size});

    print_json({ ok => 1 });
}

sub save_answer_test_data {
    bad_judge and return -1;
    my ($p) = @_;

    CATS::JudgeDB::save_answer_test_data(
        $p->{problem_id}, $p->{test_rank}, $p->{answer}, $p->{answer_size});

    print_json({ ok => 1 });
}

sub get_testset {
    bad_judge and return -1;
    my ($p) = @_;

    my %testset = CATS::Testset::get_testset($dbh, $p->{req_id}, $p->{update});

    print_json({ testset => \%testset });
}

1;
