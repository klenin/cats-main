use strict;
use warnings;

use lib '..';

use Carp;
use CATS::Problem;

my CATS::Problem $p = CATS::Problem->new;

$p->{debug} = 1;
$p->load('sample.zip', 1001, 999, 0, '');
print $p->{import_log}, "\n";

use Data::Dumper;
undef $p->{zip_archive}; 
print Dumper($p);
