package CATS::ApiJudge;

use strict;
use warnings;

use CATS::DB;
use CATS::Web;
use JSON::XS;
use CATS::Misc qw($sid);

sub print_json {
    CATS::Web::content_type('application/json');
    CATS::Web::print(encode_json(shift));
}

sub get_judge_id {
    my $id = $dbh->selectrow_array(q~
        SELECT J.id FROM judges J LEFT JOIN accounts A
        ON A.id = J.account_id WHERE A.sid = ?~, undef, $sid);
    print_json($sid ? { id => $id } : { error => "bad sid"});
    return -1;
}

1;
