use strict;
use warnings;
use utf8;

use File::Spec;
use FindBin;
use Test::More tests => 17;

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
{
    my $f = CATS::Field->new(name => 'f');

    sub fx { CATS::Field::fixed(min => 5, max => 7)->($_[0], $f) }

    ok fx('1e6'), 'not fixed';
    ok fx(4.3), 'fixed 4.3<5';
    ok fx(8.1), 'fixed 8.1<7';
    is fx(5), undef, 'fixed 5=5';
}
{
    my $f = CATS::Field->new(name => 'f');

    is_deeply $f->parse_web_param({ f => 7 }),
        { field => $f, value => 7, caption => '', error => undef }, 'field parse_web';
    is_deeply $f->parse_web_param({ g => 7 }),
        { field => $f, value => undef, caption => '', error => undef }, 'field parse_web missing';
}

{
    my $f = CATS::Form->new(
        table => 'tbl',
        fields => [ [ name => 'f1' ] ],
        href_action => '-',
    );

    my $d = { field => ($f->fields)[0], value => 8, caption => '', error => undef };
    is_deeply $f->parse_form_data({ f1 => 8 }), { ordered => [ $d ], indexed => { f1 => $d } }, 'parse_form_data';
}

{
    my $f = CATS::Form->new(
        table => 'tbl T',
        fields => [ [ name => 'f' ], [ name => 'g' ] ],
        href_action => '-',
    );
    is_deeply [ $f->route_fields ], [ f => undef, g => undef ], 'route_fields';
    is $f->fields_sql, 'T.f, T.g', 'fields_sql';
}

1;
