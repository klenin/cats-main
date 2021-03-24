use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 2;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Messages qw(msg res_str);
use CATS::Settings;

CATS::Messages::init_mockup;

$CATS::Settings::settings->{lang} = 'en';

is res_str(1234, 'a', 'b', 'c'), 'MOCKUP en 1234: [a] [b] [c]';

msg(999, 77);
is_deeply CATS::Messages::get, [ 'MOCKUP en 999: [77]' ];

1;
