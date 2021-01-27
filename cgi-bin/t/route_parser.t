use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 41;

use lib $FindBin::Bin;
use lib File::Spec->catdir($FindBin::Bin);
use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::RouteParser;
use CATS::Web::Mockup;

*pr = *CATS::RouteParser::parse_route;

*MockupWeb:: = *CATS::Web::Mockup::;
is pr(MockupWeb->new, 'zz'), 'zz', 'no params';

{
    my $w = MockupWeb->new(x => 3, z => 'z', bb => 1, id => 'abc1');
    is pr($w, [ 'y', x => integer, z => integer, bb => bool, id => ident, n => integer ]), 'y', 'route 1';
    ok !exists $w->{zz}, 'unknown';
    is $w->{x}, 3, 'integer val';
    ok !exists $w->{z}, 'integer bad';
    is $w->{bb}, 1, 'bool';
    is $w->{id}, 'abc1', 'ident';
    is $w->{n}, undef, 'absent';
}

{
    my $w = MockupWeb->new(nsi => -5, psi => '+55', ni => -5, pi => '+55', z => 0);
    is pr($w, [ 'a',
        nsi => signed_integer, psi => signed_integer,
        ni => integer, pi => integer, z => integer ]), 'a', 'route signed';
    ok !exists $w->{ni}, 'ni signed';
    ok !exists $w->{pi}, 'pi signed';
    is $w->{nsi}, -5, 'nsi signed';
    is $w->{psi}, '+55', 'psi signed';
    is $w->{z}, 0, 'zero';
}

{
    my $r = [ 'rar', ar => array_of integer ];
    my $w1 = MockupWeb->new(ar => [1, 5]);
    is pr($w1, $r), 'rar', 'route array 1';
    is_deeply $w1->{ar}, [ 1, 5 ], 'array 1';
    my $w2 = MockupWeb->new(ar => []);
    is pr($w2, $r), 'rar', 'route array 2';
    is_deeply $w2->{ar}, [], 'array 2';
    my $w3 = MockupWeb->new;
    is pr($w3, $r), 'rar', 'route array empty';
    is_deeply $w3->{ar}, [], 'array empty';
}

{
    my $r = [ 'r2', clist => clist_of integer ];
    my $w1 = MockupWeb->new(clist => '1,5,99');
    is pr($w1, $r), 'r2', 'route clist 1';
    is_deeply $w1->{clist}, [ 1, 5, 99 ], 'clist 1';
    my $w2 = MockupWeb->new(clist => '1,d,98,');
    is pr($w2, $r), 'r2', 'route clist 2';
    is_deeply $w2->{clist}, [ 1, 98 ], 'clist 2';
    my $w3 = MockupWeb->new;
    is pr($w3, $r), 'r2', 'route clist empty';
    is_deeply $w3->{clist}, [], 'clist empty';
}

{
    my $r1 = [ 'rr', enc => encoding ];
    my $w1 = MockupWeb->new(enc => 'zzz');
    is pr($w1, $r1), 'rr', 'encoding bad 1';
    is $w1->{enc}, undef, 'encoding bad 2';

    my $w2 = MockupWeb->new(enc => 'WINDOWS-1251');
    is pr($w2, $r1), 'rr', 'encoding good 1';
    is $w2->{enc}, 'WINDOWS-1251', 'encoding good 2';

    my $r2 = [ 'rr', enc => encoding_default('UTF-8') ];
    my $w3 = MockupWeb->new(enc => 'zzz');
    is pr($w3, $r2), 'rr', 'encoding default 1';
    is $w3->{enc}, 'UTF-8', 'encoding default 2';
}

is pr(MockupWeb->new, [ 'rreq', x => required integer ]), undef, 'required';

{
    my $r = [ 'rcode', qwe => sub { ($_[0] // 0) > 5 } ];
    my $w1 = MockupWeb->new(qwe => 10);
    is pr($w1, $r), 'rcode', 'route code 1';
    is $w1->{qwe}, 10, 'code 1';
    my $w2 = MockupWeb->new(qwe => 5);
    is pr($w2, $r), 'rcode', 'route code 2';
    ok !exists $w2->{qwe}, 'code 2';
}

{
    my $r = [ 'r', s => str, a => array_of integer, c => clist_of integer ];
    {
        my @orig = (s => 'xx', c => '5,6');
        my $w1 = MockupWeb->new(@orig);
        is pr($w1, $r), 'r', 'reconstruct prepare 1';
        is_deeply [ CATS::RouteParser::reconstruct($w1) ], \@orig, 'reconstruct 1';
    }
    {
        my $w1 = MockupWeb->new(s => 'xx', a => [ 3, 4 ]);
        is pr($w1, $r), 'r', 'reconstruct prepare 2';
        is_deeply [ CATS::RouteParser::reconstruct($w1, s => 'yy') ],
            [ s => 'yy', a => 3, a => 4 ], 'reconstruct 2';
    }
}

1;
