use strict;
use warnings;
use utf8;

use File::Spec;
use FindBin;
use Test::More tests => 34;

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

    sub dt { CATS::Field::date_time()->($_[0], $f) }

    is CATS::Field::date_time(allow_empty => 1)->('', $f), undef, 'date_time allow empty';
    ok dt(''), 'date_time empty';
    ok dt('sldkfj'), 'date_time bad';
    is dt('1.2.3'), undef, 'date_time no time';
    ok dt('40.10.2000'), 'date_time bad day';
    ok dt('4.15.2000'), 'date_time bad month';
    ok dt('4.10.999999'), 'date_time bad year';
    is dt('29.2.2000'), undef, 'date_time leap';
    ok dt('29.2.2001'), 'date_time not leap';
    is dt('1.2.3 5:6'), undef, 'date_time time';
    ok dt('1.2.3 25:6'), 'date_time bad hour';
    ok dt('1.2.3 5:60'), 'date_time bad minute';
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
    );

    my $d = { field => ($f->fields)[0], value => 8, caption => '', error => undef };
    is_deeply $f->parse_form_data({ f1 => 8 }), { ordered => [ $d ], indexed => { f1 => $d } }, 'parse_form_data';
}
{
    my $f = CATS::Form->new(
        table => 'tbl',
        fields => [ [ name => 'f1' ], [ name => 'f2', default => 5 ], [ name => 'f3', default => sub { 7 } ], ],
    );

    my @fields = $f->fields;
    is $fields[1]->default, 5, 'field default';
    my $fs = $f->make;
    is_deeply $f->make, [ '', 5, 7 ], 'make default';
}
{
    my $f = CATS::Form->new(
        table => 'tbl T',
        fields => [ [ name => 'f' ], [ name => 'g' ] ],
    );
    is_deeply [ $f->route_fields ], [ f => undef, g => undef ], 'route_fields';
    is $f->fields_sql, 'T.f, T.g', 'fields_sql';
}

{
    my $saved = 0;
    my $f = CATS::Form->new(
        table => 'tbl',
        fields => [ [ name => 'f1' ] ],
        override_load => sub {},
        override_save => sub {
            my ($self, $id, $data) = @_;
            $saved = 1;
            is_deeply $data, [ 8 ], 'save';
            57;
        },
        before_display => sub {
            my ($form_data, $p) = @_;
            is $form_data->{href_action}, 'action?id=57', 'href_action';
        },
        href_action => 'action',
    );

    $f->edit_frame({ f1 => 8, edit_save => 1 });
    ok $saved, 'saved';
}

1;
