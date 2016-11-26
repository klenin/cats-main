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
use JSON::XS;

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
use CATS::DevEnv;
use CATS::Misc qw(:all);
use CATS::Utils qw(url_function);
use CATS::Data qw(:all);
use CATS::IP;
use CATS::RankTable;
use CATS::StaticPages;
use CATS::TeX::Lite;
use CATS::Testset;
use CATS::User;
use CATS::Router;

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

use LWP::UserAgent;

my @whitelist = qw(www.codechef.com judge.u-aizu.ac.jp compprog.win.tue.nl stats.ioinformatics.org scoreboard.ioinformatics.org rosoi.net);

sub handler {
    my $r = shift;    
    init_request($r);
    return CATS::Web::not_found unless CATS::Router::parse_uri;
    if ((param('f') || '') eq 'proxy') {
        my $url = param('u') or die;
        my $r = join '|', map "\Q$_\E", @whitelist;
        $url =~ m[^http(s?)://($r)/] or die;
        my $is_https = $1;
        my $ua = LWP::UserAgent->new;
        # Workaround for LWP bug with https proxies, see http://www.perlmonks.org/?node_id=1028125
        # Use postfix 'if' to avoid trapping 'local' inside a block.
        local $ENV{https_proxy} = $CATS::Config::proxy if $CATS::Config::proxy;
        $ua->proxy($is_https ? (https => undef) : (http => "http://$CATS::Config::proxy")) if $CATS::Config::proxy;
        my $res = $ua->request(HTTP::Request->new(GET => $url, [ 'Accept', '*/*' ]));
        $res->is_success or die sprintf 'proxy http error: url=%s result=%s', $url, $res->status_line;
        if ((my $json = param('json')) =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/) {
            CATS::Web::content_type('application/json');
            print $json, '(', encode_json({ result => $res->content }), ')';
        }
        else {
            CATS::Web::content_type('text/plain');
            print $res->content;
        }
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
