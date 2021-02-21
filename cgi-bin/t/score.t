use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 14;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Score;

is CATS::Score::_round(5.1, 1), 5, 'round 1';
is CATS::Score::_round(5.19, 0.1), 5.1, 'round 0.1';

is CATS::Score::scale_points(undef, { scaled_points => 2 }), undef, 'scale_points undef';
is CATS::Score::scale_points(3, {}), 3, 'scale_points 3';

is CATS::Score::scale_points(1, { scaled_points => 4 }), 4, 'scale_points rescale up';
is CATS::Score::scale_points(3, { scaled_points => 1, max_points => 10 }), 0.3, 'scale_points rescale down';
is CATS::Score::scale_points(1,
    { scaled_points => 1, max_points => 3, round_points_to => 0.01 }), 0.33, 'scale_points rescale round';
is CATS::Score::scale_points(75,
    { max_points => 100, round_points_to => 10 }), 70, 'scale_points round';

{
    *da = *CATS::Score::dependencies_accepted;
    my $ts2 = { name => 't2', depends_on => 't1' };
    my $all = [ { name => 't1' }, $ts2 ];
    my $cache = {};
    is da($all, $ts2, { t1 => 1 }, $cache), 1, 'dependencies_accepted 1';
    is da($all, $ts2, {}, $cache), 1, 'dependencies_accepted cached';
    is da($all, $ts2, {}, {}), 1, 'dependencies_accepted 0';
}

sub abp {
    my $d = [ map +{ f => $_ }, @_ ];
    CATS::Score::align_by_point($d, 'f');
    [ map $_->{f}, @$d ];
}

{
    is_deeply abp(1, 0, 3), [ qw(1 0 3) ], 'abp 0';
    is_deeply abp('1.0', 2, '3.'), [ qw(1.0 2.0 3.0) ], 'abp 1';
    is_deeply abp(111.1, 2.34, '13'), [ qw(111.10 2.34 13.00) ], 'abp 2';
}

1;
