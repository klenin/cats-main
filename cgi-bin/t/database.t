use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 3;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Constants;
use CATS::DB;

CATS::DB::sql_connect({});

ok $dbh, 'connect';

ok my $anon = $dbh->selectrow_hashref(q~
    SELECT * FROM accounts WHERE login = ?~, { Slice => {} },
    $cats::anonymous_login), 'anonymous exists';
is $anon->{locked}, 1, 'anonymous locked';
