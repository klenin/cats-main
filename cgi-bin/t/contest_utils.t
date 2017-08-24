use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 6;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Contest::Utils;

*csp = *CATS::Contest::Utils::common_seq_prefix;

is_deeply csp([], []), [], 'empty both';
is_deeply csp([ 'a' ], []), [], 'empty a';
is_deeply csp([ 'a' ], [ 'b' ]), [], 'empty b';

{
    my $abc = [ 'a', 'b', 'c' ];
    is_deeply csp([ 'a', 'b' ], [ 'b', 'c' ]), [], 'no prefix';
    is_deeply csp($abc, [ 'a', 'b', 'd' ]), [ 'a', 'b' ], 'prefix 2';
    is_deeply csp($abc, $abc), $abc, 'prefix 3';
}
