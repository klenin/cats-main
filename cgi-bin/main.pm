#!/usr/bin/perl
package main;

use strict;
use warnings;
#use encoding 'utf8', STDIN => undef;

use Data::Dumper;
use DBI::Profile;
use FindBin;
use SQL::Abstract; # Actually used by CATS::DB, bit is optional there.

my $cats_lib_dir;
my $cats_problem_lib_dir;
BEGIN {
    $cats_lib_dir = $ENV{CATS_DIR} || $FindBin::Bin;
    $cats_lib_dir =~ s/\/$//;
    $cats_problem_lib_dir = "$cats_lib_dir/cats-problem";
    $Data::Dumper::Terse = 1;
    $Data::Dumper::Indent = 1;
}

use lib $cats_lib_dir;
use lib $cats_problem_lib_dir;

use CATS::DB;
use CATS::Globals qw($t);
use CATS::Init;
use CATS::MainMenu;
use CATS::Output;
use CATS::Proxy;
use CATS::Router;
use CATS::Settings;
use CATS::StaticPages;
use CATS::Time;
use CATS::Web qw(param);

sub accept_request {
    my ($p) = @_;
    my $output_file = '';
    if (CATS::StaticPages::is_static_page($p)) {
        $output_file = CATS::StaticPages::process_static($p)
            or return;
    }
    CATS::Init::initialize($p);
    return if $p->has_error;
    CATS::Time::mark_init;

    if (!defined $t) {
        my $fn = CATS::Router::route($p);
        # Function returns -1 if there is no need to generate output, e.g. a redirect was issued.
        ($fn->($p) || 0) == -1 and return;
    }
    CATS::Settings::save;

    defined $t or return;
    CATS::MainMenu->new({ f => $p->{f} })->generate;
    CATS::Time::mark_finish unless param('notime');
    CATS::Output::generate($p, $output_file);
}

sub handler {
    my ($r) = @_;

    my $p = CATS::Web->new;
    $p->init_request($r);
    return $p->not_found unless CATS::Router::parse_uri($p);

    CATS::Router::common_params($p);

    if ($p->{f} eq 'proxy') {
        return CATS::Proxy::proxy($p, param('u'));
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

    accept_request($p);
    $dbh->rollback;

    $p->get_return_code;
}

1;
