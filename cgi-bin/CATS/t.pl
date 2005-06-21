use strict;
use warnings;
use lib '..';
use CATS::Data qw(:all);
use CATS::Misc qw(:all);
use Data::Dumper;

sql_connect;
print Dumper([get_contests_info([531343,531545])]);
sql_disconnect;
