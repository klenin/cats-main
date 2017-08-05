package CATS::Time;

use strict;
use warnings;

use CATS::Misc qw($contest $t $user res_str);

sub prepare_server_time {
    my $dt = $contest->{time_since_start} - $user->{diff_time};
    $t->param(
        server_time => $contest->{server_time},
        elapsed_msg => res_str($dt < 0 ? 578 : 579),
        elapsed_time => format_diff(abs($dt)),
    );
}

sub format_diff {
    my ($dt, $display_plus) = @_;
    $dt or return '';
    my $sign = $dt < 0 ? '-' : $display_plus ? '+' : '';
    $dt = abs($dt);
    my $days = int($dt);
    $dt = ($dt - $days) * 24;
    my $hours = int($dt);
    $dt = ($dt - $hours) * 60;
    my $minutes = int($dt + 0.5);
    !$days && !$hours ? $minutes :
        sprintf($days ? '%s%d%s %02d:%02d' : '%s%4$d:%5$02d', $sign, $days, res_str(577), $hours, $minutes);
}

1;
