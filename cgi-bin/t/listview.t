use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 7;

use lib File::Spec->catdir($FindBin::Bin);
use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Globals qw($t);
use CATS::ListView;
use CATS::Messages qw(res_str);
use CATS::Template;
use CATS::Web::Mockup qw(res_str);

$t = CATS::Template->new_dummy;

my $web = CATS::Web::Mockup->new;
my $lv = CATS::ListView->new(web => $web, name => 'test', url => 'localhost');
ok $lv, 'new';

$lv->default_sort(0)->define_columns([ { caption => 'colA', order_by => 'colA' } ]);
{
    my $i = 0;
    my $raw = [ 5, 6, 7 ];
    $lv->attach(sub { $i < @$raw ? (v => $raw->[$i++]) : () });
    is_deeply $t->get_params->{test}, [ { v => 5 }, { v => 6 }, { v => 7 } ], 'simple';

    is $lv->order_by, 'ORDER BY colA ASC', 'order_by';
    is $lv->order_by('x'), 'ORDER BY x, colA ASC', 'order_by pre_sort';
    $lv->settings->{sort_dir} = 1;
    is $lv->order_by, 'ORDER BY colA DESC', 'order_by desc';
    $lv->settings->{sort_by} = 99;
    is $lv->order_by, '', 'order_by none';
    is $lv->order_by('y'), 'ORDER BY y', 'order_by pre_sort only';
}

1;
