package CATS::Time;

use strict;
use warnings;

use Time::HiRes;

use CATS::Messages qw(res_str);
use CATS::Globals qw($contest $t $user);
use CATS::Web qw(param);

sub prepare_server_time {
    my $dt = $contest->{time_since_start} - $user->{diff_time};
    $t->param(
        server_time => $contest->{server_time},
        elapsed_msg => res_str($dt < 0 ? 578 : 579),
        elapsed_time => format_diff(abs($dt)),
    );
}

my $half_minute = 0.5 / 24 / 60;

sub format_diff {
    my ($dt, $display_plus) = @_;
    $dt or return '';
    my $sign = $dt < 0 ? '-' : $display_plus ? '+' : '';
    $dt = abs($dt) + $half_minute;
    my $days = int($dt);
    $dt = ($dt - $days) * 24;
    my $hours = int($dt);
    $dt = ($dt - $hours) * 60;
    my $minutes = int($dt);
    !$days && !$hours ? $sign. sprintf('0:%02d', $minutes) :
        sprintf($days ? '%s%d%s %02d:%02d' : '%s%4$d:%5$02d', $sign, $days, res_str(577), $hours, $minutes);
}

sub format_diff_ext {
    my ($diff, $ext, $display_plus) = @_;
    format_diff($diff, $display_plus) . ($ext ? ' ... ' . format_diff($ext, $display_plus) : '');
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
    my ($obj, $p, $prefix) = @_;
    my $k = $diff_units->{$p->{$prefix . '_units'} // ''} or return;
    my $n = $prefix . '_time';
    $obj->{$n} = $p->{$n} ? $p->{$n} * $k : undef;
    1;
}

our $diff_time_sql = '(COALESCE(CA.diff_time, 0) + COALESCE(CS.diff_time, 0))';
our $ext_time_sql = '(COALESCE(CA.ext_time, 0) + COALESCE(CS.ext_time, 0))';
our $contest_start_offset_sql = "(C.start_date + $diff_time_sql)";
our $contest_finish_offset_sql = "(C.finish_date + $diff_time_sql + $ext_time_sql)";
our $contest_site_finish_sql = "(C.finish_date + COALESCE(CS.diff_time, 0) + COALESCE(CS.ext_time, 0))";

1;
