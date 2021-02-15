package CATS::Score;

sub _round { int($_[0] * 10 + 0.5) / 10 }

sub scale_points {
    my ($points, $problem) = @_;
    $points && (
    $problem->{scaled_points} ?
        _round($points * $problem->{scaled_points} / ($problem->{max_points} || 1)) : $points);

}

1;
