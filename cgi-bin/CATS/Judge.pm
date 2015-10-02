package CATS::Judge;

use strict;
use warnings;

use CATS::DB;
use CATS::Config;

sub ping {
    my ($jid) = @_;
    $dbh->do(qq~
        UPDATE judges SET is_alive = 0 WHERE is_alive = 1 AND id = ?~, undef,
        $jid);
    $dbh->commit;
}

1;
