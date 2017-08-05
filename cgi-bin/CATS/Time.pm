package CATS::Time;

use strict;
use warnings;

use Time::HiRes;

use CATS::Misc qw($contest $t $user res_str);
use CATS::Web qw(param);

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

my ($start_time, $init_time);

sub mark_start { $start_time = [ Time::HiRes::gettimeofday ] }

sub mark_init { $init_time = Time::HiRes::tv_interval($start_time, [ Time::HiRes::gettimeofday ]) }

sub mark_finish {
    return if param('notime');
    $t->param(
        request_process_time => sprintf('%.3fs',
            Time::HiRes::tv_interval($start_time, [ Time::HiRes::gettimeofday ])),
        init_time => sprintf('%.3fs', $init_time || 0),
    );
    prepare_server_time;
}

my $diff_units = { min => 1 / 24 / 60, hour => 1 / 24, day => 1, week => 7 };

sub set_diff_time {
    my ($obj, $p) = @_;
    my $k = $diff_units->{$p->{units} // ''} or return;
    $obj->{diff_time} = $p->{diff_time} ? $p->{diff_time} * $k : undef;
    1;
}

1;
