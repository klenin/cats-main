use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 6;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Config;
use CATS::IP;

$ENV{REMOTE_ADDR} = '1.2.3.4';

is CATS::IP::get_ip, '1.2.3.4', 'get_ip';

%CATS::Config::ip_aliases = (
    localhost => qr/^127\.0\.0\.1$/,
);

is CATS::IP::filter_ip('127.0.0.1'), 'localhost', 'filter_ip';
{
    my %s = CATS::IP::linkify_ip('127.0.0.1,4.3.2.1');
    is $s{last_ip_short}, '4.3.2.1', 'linkify_ip short';
    is $s{last_ip}, 'localhost, 4.3.2.1', 'linkify_ip';
}

@CATS::Config::ip_blocked_regexps = (
    localhost => qr/^5\.6\.7\.8$/,
);

ok !CATS::IP::is_blocked('1.2.3.4, 15.6.7.8'), 'is_blocked 0';
ok CATS::IP::is_blocked('1.2.3.4, 5.6.7.8'), 'is_blocked 1';

1;
