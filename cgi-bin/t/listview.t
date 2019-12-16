use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 1;

use lib File::Spec->catdir($FindBin::Bin);
use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use MockupWeb;
use CATS::ListView;
use CATS::Messages qw(res_str);

my $lv = CATS::ListView->new(web => MockupWeb->new, name => 'test');
ok $lv, 'new';

1;
