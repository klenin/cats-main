use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 10;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Output;

*cq = *CATS::Output::_csv_quote;

is cq(1), '1', 'csv quote 1';
is cq('a_b'), 'a_b', 'csv quote a_b';
is cq('a b'), '"a b"', 'csv quote space';
is cq("a\tb"), qq~"a\tb"~, 'csv quote tab';
is cq('"a"'), '"""a"""', 'csv quote quote';
is cq('text "a" text'), '"text ""a"" text"', 'csv quote quote 2';
is cq([ qw(a bc) ]), '"a bc"', 'csv array';

is CATS::Output::_generate_csv(
    { csv => [ 'a' , 'b' ] }, { lv_array_name => 'r',
    r => [ { a => 1, b => '2 3', c => 4 }, { b => '"' } ] }),
    qq~a\tb\n1\t"2 3"\n\t""""~, 'generate_csv';
is CATS::Output::_generate_csv(
    { csv => [ 'a' , 'b' ], csv_sep => ',' },
    { lv_array_name => 'r', r => [ { a => 1, b => '2' } ] }),
    qq~a,b\n1,2~, 'generate_csv sep';
is CATS::Output::_generate_csv(
    { csv => [ 'a' , 'b' ] }, { lv_array_name => 'r', r => [ [ 5, 6 ] ] }),
    qq~a\tb\n5\t6~, 'generate_csv array';
