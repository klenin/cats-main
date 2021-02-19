use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 8;

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

1;
