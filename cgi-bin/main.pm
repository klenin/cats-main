#!/usr/bin/perl
package main;

use strict;
use warnings;
use encoding 'utf8', STDIN => undef;

use Encode;

use Data::Dumper;
use DBI::Profile;
use Storable ();
use Time::HiRes;

our $cats_lib_dir;
our $cats_problem_lib_dir;
BEGIN {
    $cats_lib_dir = $ENV{CATS_DIR} || '.';
    $cats_lib_dir =~ s/\/$//;
    $cats_problem_lib_dir = "$cats_lib_dir/cats-problem";
    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 1;
}

use lib $cats_lib_dir;
use lib $cats_problem_lib_dir;

use CATS::DB;
use CATS::Config;
use CATS::MainMenu;
use CATS::Misc qw($t initialize save_settings generate_output);
use CATS::Proxy;
use CATS::Router;
use CATS::StaticPages;
use CATS::Time;
use CATS::Web qw(param url_param redirect init_request get_return_code has_error);

my ($request_start_time, $init_time);

sub accept_request {
    my $output_file = '';
    if (CATS::StaticPages::is_static_page) {
        $output_file = CATS::StaticPages::process_static()
            or return;
    }
    initialize;
    return if has_error;
    $init_time = Time::HiRes::tv_interval($request_start_time, [ Time::HiRes::gettimeofday ]);

    unless (defined $t) {
        my ($fn, $p) = CATS::Router::route;
        # Function returns -1 if there is no need to generate output, e.g. a redirect was issued.
        ($fn->($p) || 0) == -1 and return;
    }
    save_settings;

    defined $t or return;
    CATS::MainMenu::generate_menu;
    unless (param('notime')) {
        $t->param(request_process_time => sprintf '%.3fs',
            Time::HiRes::tv_interval($request_start_time, [ Time::HiRes::gettimeofday ]));
        $t->param(init_time => sprintf '%.3fs', $init_time || 0);
    }
    CATS::Time::prepare_server_time;
    generate_output($output_file);
}

sub handler {
    my $r = shift;
    init_request($r);
    return CATS::Web::not_found unless CATS::Router::parse_uri;
    if ((param('f') || '') eq 'proxy') {
        CATS::Proxy::proxy;
        return get_return_code();
    }
    $request_start_time = [ Time::HiRes::gettimeofday ];
    CATS::DB::sql_connect({
        ib_timestampformat => '%d.%m.%Y %H:%M',
        ib_dateformat => '%d.%m.%Y',
        ib_timeformat => '%H:%M:%S',
    });
    $dbh->rollback; # In a case of abandoned transaction
    $DBI::Profile::ON_DESTROY_DUMP = undef;
    $dbh->{Profile} = DBI::Profile->new(Path => []); # '!Statement'
    $dbh->{Profile}->{Data} = undef;

    accept_request;
    $dbh->rollback;

    return get_return_code();
}

1;
