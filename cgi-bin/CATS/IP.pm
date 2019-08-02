package CATS::IP;

use strict;
use warnings;

use List::Util qw(first);

use CATS::Config;

sub filter_ip {
    my ($ip) = @_;
    defined $ip or return undef;
    for (keys %CATS::Config::ip_aliases) {
        return $_ if $ip =~ $CATS::Config::ip_aliases{$_};
    }
    $ip;
}

sub get_ip {
   join ', ', grep $_ ne '',
       ($ENV{HTTP_X_FORWARDED_FOR} || ''), ($ENV{REMOTE_ADDR} || '');
}

sub local_ip { $_[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/ ? $1 == 10 || $1 == 192 && $2 == 168 : 1; }

sub linkify_ip {
    my ($ip) = $_[0] || '';
    my (@ips) = map filter_ip($_), split /[,\s]+/, $ip;
    my $short = (first { !local_ip($_) } @ips) || $ips[0] || '';
    (
        last_ip_short => $short,
        last_ip => (@ips > 1 ? join(', ', @ips) : ''),
        $short ? (href_whois => sprintf $CATS::Config::ip_info, $short) : (),
    )
}

# See https://2019.www.torproject.org/projects/tordnsel.html.en

my $https_port = 443;
my $some_google_ip = '216.58.206.110';
my $tor_dnsel = 'ip-port.exitlist.torproject.org';

sub is_tor {
    my ($ip) = @_;
    my @parts = $ip =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/ or return;
    my $reversed_parts = join '.', reverse @parts;
    my $out = `nslookup -timeout=1 $reversed_parts.$https_port.$some_google_ip.$tor_dnsel`;
    $out =~ /Address:\s+127\.0\.0\.2/ ? 1 : undef;
}

1;
