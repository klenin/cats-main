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

1;
