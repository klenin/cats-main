use strict;
use warnings;
use utf8;

use File::Spec;
use FindBin;
use Test::More tests => 8;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

BEGIN { $ENV{CATS_DIR} = File::Spec->catdir($FindBin::Bin, '..'); }
use CATS::Form;

CATS::Messages::init;

{
    my $f = CATS::Field->new(name => 'f');

    local *sl = *CATS::Field::str_length;
    ok sl(1, 3)->('abcd', $f), 'str_length 4>3';
    ok sl(2, 3)->('a', $f), 'str_length 1<2';
    is sl(1, 3)->('abc', $f), undef, 'str_length 3=3';

    ok sl(1, 4)->('эюя', $f), 'str_length ru 6>4';
    is sl(1, 4)->('эю', $f), undef, 'str_length ru 4=4';
}
{
    my $f = CATS::Field->new(name => 'f');

    sub ir { CATS::Field::int_range(min => 5, max => 7)->($_[0], $f) }

    ok ir(4), 'int_range 4<5';
    ok ir(8), 'int_range 8<7';
    is ir(5), undef, 'int_range 5=5';
}

1;