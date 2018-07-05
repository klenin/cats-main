use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 18;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

package MockupWeb;

sub new {
    my ($class, %rest) = @_;
    bless { p => \%rest }, $class
}

sub web_param { $_[0]->{p}->{$_[1]} }

package main;

use CATS::RouteParser;

*pr = *CATS::RouteParser::parse_route;

is pr(MockupWeb->new, 'zz'), 'zz', 'no params';

{
    my $w = MockupWeb->new(x => 3, z => 'z', bb => 1, id => 'abc1');
    is pr($w, [ 'y', x => integer, z => integer, bb => bool, id => ident ]), 'y', 'route 1';
    ok !exists $w->{zz}, 'unknown';
    is $w->{x}, 3, 'integer val';
    ok !exists $w->{z}, 'integer bad';
    is $w->{bb}, 1, 'bool';
    is $w->{id}, 'abc1', 'ident';
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

1;
