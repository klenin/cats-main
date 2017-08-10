#!/usr/bin/perl
package main;

use strict;
use warnings;
use encoding 'utf8', STDIN => undef;

use Data::Dumper;
use DBI::Profile;
use Storable ();

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
use CATS::Init;
use CATS::MainMenu;
use CATS::Messages;
use CATS::Misc qw($t generate_output);
use CATS::Proxy;
use CATS::Router;
use CATS::Settings;
use CATS::StaticPages;
use CATS::Time;
use CATS::Web qw(has_error get_return_code init_request param redirect url_param);

sub accept_request {
    my $output_file = '';
    if (CATS::StaticPages::is_static_page) {
        $output_file = CATS::StaticPages::process_static()
            or return;
    }
    CATS::Init::initialize;
    return if has_error;
    CATS::Time::mark_init;

    unless (defined $t) {
        my ($fn, $p) = CATS::Router::route;
        # Function returns -1 if there is no need to generate output, e.g. a redirect was issued.
        ($fn->($p) || 0) == -1 and return;
    }
    CATS::Settings::save;

    defined $t or return;
    CATS::MainMenu::generate_menu;
    CATS::Time::mark_finish;
    $t->param(lang => CATS::Messages::lang);
    generate_output($output_file, CATS::Settings::as_cookie(CATS::Messages::lang));
}

sub handler {
    my $r = shift;
    init_request($r);
    return CATS::Web::not_found unless CATS::Router::parse_uri;
    if ((param('f') || '') eq 'proxy') {
        CATS::Proxy::proxy;
        return get_return_code();
    }
    CATS::Time::mark_start;
    CATS::DB::sql_connect({
        ib_timestampformat => '%d.%m.%Y %H:%M',
        ib_dateformat => '%d.%m.%Y',
        ib_timeformat => '%H:%M:%S',
    });
    $dbh->rollback; # In a case of abandoned transaction.
    $DBI::Profile::ON_DESTROY_DUMP = undef;
    $dbh->{Profile} = DBI::Profile->new(Path => []); # '!Statement'
    $dbh->{Profile}->{Data} = undef;

    accept_request;
    $dbh->rollback;

    return get_return_code();
}

1;
