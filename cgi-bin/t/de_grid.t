use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 5;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::DeGrid;

*cdm = *CATS::DeGrid::matrix;
*cdi = *CATS::DeGrid::calc_deletes_inserts;

is_deeply cdm([ 1 ], 1), [ [ 1 ] ], 'matrix 1';
is_deeply cdm([ 1 .. 6 ], 2), [ [ 1, 4 ], [ 2, 5 ], [ 3, 6 ] ], 'matrix 2';
is_deeply cdm([ 1 .. 6 ], 3), [ [ 1, 3, 5 ], [ 2, 4, 6 ] ], 'matrix 3';

sub ic { { id => $_[0], checked => $_[1] } }
is_deeply [ cdi([ ic(1, 0), ic(2, 1), ic(3, 0) ], [ 2 ], 'id', 'checked') ], [ [], [] ],
    'deletes_inserts 0';
is_deeply [ cdi([ ic(1, 1), ic(2, 1), ic(3, 0) ], [ 1, 3 ], 'id', 'checked') ], [ [ 2 ], [ 3 ] ],
    'deletes_inserts';
