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
    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT_OK = qw(handler);
    our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);
}
use lib $cats_lib_dir;
use lib $cats_problem_lib_dir;


use CATS::Web qw(param url_param redirect init_request get_return_code);
use CATS::DB;
use CATS::Config;
use CATS::Constants;
use CATS::BinaryFile;
use CATS::Misc qw(
    $is_jury $uid $sid $contest $is_virtual $t
    res_str url_f get_anonymous_uid initialize save_settings generate_output attach_menu);
use CATS::Utils qw(url_function);
use CATS::Proxy;
use CATS::Router;
use CATS::StaticPages;

sub generate_menu {
    my $logged_on = $sid ne '';

    my @left_menu = (
        { item => $logged_on ? res_str(503) : res_str(500),
          href => $logged_on ? url_function('logout', sid => $sid) : url_function('login') },
        { item => res_str(502), href => url_f('contests') },
        { item => res_str(525), href => url_f('problems') },
        ($is_jury || !$contest->is_practice ? { item => res_str(526), href => url_f('users') } : ()),
        { item => res_str(510),
          href => url_f('console', $is_jury ? () : (uf => $uid || get_anonymous_uid())) },
        ($is_jury ? () : { item => res_str(557), href => url_f('import_sources') }),
    );

    if ($is_jury) {
        push @left_menu, (
            { item => res_str(548), href => url_f('compilers') },
            { item => res_str(545), href => url_f('similarity') }
        );
    }
    else {
        push @left_menu, (
            { item => res_str(517), href => url_f('compilers') },
            { item => res_str(549), href => url_f('keywords') } );
    }

    unless ($contest->is_practice) {
        push @left_menu, ({
            item => res_str(529),
            href => url_f('rank_table', $is_jury ? () : (cache => 1, hide_virtual => !$is_virtual))
        });
    }

    my @right_menu = ();

    if ($uid && (url_param('f') ne 'logout')) {
        @right_menu = ( { item => res_str(518), href => url_f('settings') } );
    }

    push @right_menu, (
        { item => res_str(544), href => url_f('about') },
        { item => res_str(501), href => url_f('registration') } );

    attach_menu('left_menu', undef, \@left_menu);
    attach_menu('right_menu', 'about', \@right_menu);
}

sub accept_request {
    my $output_file = '';
    if (CATS::StaticPages::is_static_page) {
        $output_file = CATS::StaticPages::process_static()
            or return;
    }
    initialize;
    $CATS::Misc::init_time = Time::HiRes::tv_interval(
        $CATS::Misc::request_start_time, [ Time::HiRes::gettimeofday ]);

    unless (defined $t) {
        my ($fn, $p) = CATS::Router::route;
        # Function returns -1 if there is no need to generate output, e.g. a redirect was issued.
        ($fn->($p) || 0) == -1 and return;
    }
    save_settings;

    generate_menu if defined $t;
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
    $CATS::Misc::request_start_time = [ Time::HiRes::gettimeofday ];
    CATS::DB::sql_connect({
        ib_timestampformat => '%d.%m.%Y %H:%M',
        ib_dateformat => '%d.%m.%Y',
        ib_timeformat => '%H:%M:%S',
    });
    $dbh->rollback; # In a case of abandoned transaction
    $DBI::Profile::ON_DESTROY_DUMP = undef;
    $dbh->{Profile} = DBI::Profile->new(Path => []); # '!Statement'
    $dbh->{Profile}->{Data} = undef;

    accept_request();
    $dbh->rollback;

    return get_return_code();
}

1;
