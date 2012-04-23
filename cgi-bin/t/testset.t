use strict;
use warnings;

use lib '..';

use Test::More;
use Test::Exception;

use CATS::Testset;

my $testsets = {
  't1' => { tests => '1,2,3' },
  't2' => { tests => 't1' },
  'tr1' => { tests => 'tr2' },
  'tr2' => { tests => 'tr1' },
  'sc1' => { tests => '1-5', points => 10 },
  'sc2' => { tests => '5-6', points => 20 },
  'scn' => { tests => 'sc1,3', points => 7 },
  'sc' => { tests => 'sc1' },
  'sca' => { tests => 'sc,sc2' },
};

sub ptr { CATS::Testset::parse_test_rank($testsets, @_, sub { die @_ }) }

sub h { my %h; @h{@_} = undef; \%h; }

plan tests => 3;

subtest 'basic', sub {
    is_deeply(ptr('1'), h(1));
    is_deeply(ptr('1,3'), h(1, 3));
    is_deeply(ptr('2-4'), h(2 .. 4));
    is_deeply(ptr(' 1, 7 - 8, 3 - 9 '), h(1, 3 .. 9));

    throws_ok { ptr('') } qr/empty/i;
    throws_ok { ptr(',') } qr/empty/i;
    throws_ok { ptr('?') } qr/bad/i;
};

subtest 'testsets', sub {
    is_deeply(ptr('t1'), h(1 .. 3));
    is_deeply(ptr('t2'), h(1 .. 3));
    throws_ok { ptr('x') } qr/unknown testset/i;
    throws_ok { ptr('tr2') } qr/recursive/i;
};

subtest 'scoring groups', sub {
    my %t1 = map { $_ => $testsets->{sc1} } 1..5;
    is_deeply(ptr('sc1'), \%t1);
    is_deeply(ptr('sc'), \%t1);
    is_deeply(ptr('sc, 9'), { %t1, 9 => undef });
    throws_ok { ptr('scn') } qr/nested/i;
    throws_ok { ptr('sc1,sc2') } qr/ambiguous/i;
    throws_ok { ptr('sca') } qr/ambiguous/i;
};

done_testing;
