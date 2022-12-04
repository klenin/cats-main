use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::Exception;
use Test::More tests => 5;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Settings;

*get = *CATS::Settings::get_item;
*update = *CATS::Settings::update_item;

{

    my $s = { key1 => 'abc' };
    is get($s, { name => 'key1' }), 'abc', 'get';
    is get($s, { name => 'key2' }), undef, 'get none';

    update($s, { name => 'key1' }, 'def');
    is get($s, { name => 'key1' }), 'def', 'get 2';
    update($s, { name => 'key1', default => 'def' }, 'def');
    is get($s, { name => 'key1' }), undef, 'get default';

    update($s, { name => 'a.b.c.d' }, 'x');
    is_deeply get($s, { name => 'a.b' }), { c => { d => 'x' } }, 'nested';
}

1;
