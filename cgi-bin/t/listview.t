use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 2;

use lib File::Spec->catdir($FindBin::Bin);
use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Globals qw($t);
use CATS::ListView;
use CATS::Messages qw(res_str);

use MockupWeb;
use MockupTemplate;

$t = MockupTemplate->new;

my $lv = CATS::ListView->new(web => MockupWeb->new, name => 'test', url => 'localhost');
ok $lv, 'new';

$lv->default_sort(0)->define_columns([ { caption => 'colA', order_by => 'colA' } ]);
{
    my $i = 0;
    my $raw = [ 5, 6, 7 ];
    $lv->attach(sub { $i < @$raw ? (v => $raw->[$i++]) : () });
    is_deeply $t->get_params->{test}, [ { v => 5 }, { v => 6 }, { v => 7 } ], 'simple';
}

1;
