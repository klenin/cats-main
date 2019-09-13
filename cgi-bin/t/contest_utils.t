use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 14;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Contest::Utils;

*csp = *CATS::Contest::Utils::common_seq_prefix;
*cp = *CATS::Contest::Utils::common_prefix;

is_deeply csp([], []), [], 'csp empty both';
is_deeply csp([ 'a' ], []), [], 'csp empty a';
is_deeply csp([ 'a' ], [ 'b' ]), [], 'csp empty b';

{
    my $abc = [ 'a', 'b', 'c' ];
    is_deeply csp([ 'a', 'b' ], [ 'b', 'c' ]), [], 'csp no prefix';
    is_deeply csp($abc, [ 'a', 'b', 'd' ]), [ 'a', 'b' ], 'csp prefix 2';
    is_deeply csp($abc, $abc), $abc, 'csp prefix 3';
}

is cp(), '', 'cp empty 1';
is cp(''), '', 'cp empty 2';
is cp('abc'), 'abc', 'cp 1';
is cp('abc def', 'abc xyz'), 'abc', 'cp 2';
is cp('abc_def', 'abc    def  m'), 'abc def', 'cp separators';
is cp('x  1 2', 'x__1__3'), 'x 1', 'cp nums';
is cp('a b c d e', 'a  b c d f', 'a b  c e f'), 'a b c', 'cp 3';
is cp('x:1', 'x,2'), 'x', 'cp comma';
