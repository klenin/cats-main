use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::Exception;
use Test::More tests => 10;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Topics;

{
    my $t1 = { code_prefix => 'A' };
    my $t2 = { code_prefix => 'B' };
    my $t = CATS::Topics->new([ $t1, $t2 ]);
    is_deeply $t->get('A'), $t1, 'A';
    is_deeply $t->get('A1'), $t1, 'A1';
    is_deeply $t->get('B'), $t2, 'B 1';
    throws_ok { $t->add($t1) } qr/duplicate.*A/i, 'add duplicate';
    my $t3 = { code_prefix => 'B2' };
    my $t4 = { code_prefix => 'B21' };
    $t->add($t3);
    $t->add($t4);
    is_deeply $t->get('B'), $t2, 'B 2';
    is_deeply $t->get('B2'), $t3, 'B2';
    is_deeply $t->get('B3'), $t2, 'B3';
    is_deeply $t->get('B213'), $t4, 'B213';
    is $t->get('Z'), undef, 'Z';
    is $t->get(undef), undef, 'undef';
}

1;
