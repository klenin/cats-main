#!perl -w

use strict;
use lib './';
use FileHandle;
use DBD::Oracle qw(:ora_types);

use CATS;
use CATS_misc (':all');

sql_connect;


$dbh->do(qq~UPDATE judges SET jsid=NULL~);
$dbh->commit;

sql_disconnect;

1;
