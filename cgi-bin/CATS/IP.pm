package CATS::IP;

use strict;
use warnings;

use List::Util qw(first);

sub filter_ip
{
    my ($ip) = @_;
    defined $ip or return;
    for ($ip)
    {
        #s/195.209.254.222/pin/;
        #s/195.209.254.4/www/;
        #s/195.209.254.3/proxy/;
        s/77.234.208.5/dvgu/;
        s/77.234.208.4/proxy/;
        s/192.168.9.5/dvgu/;
        s/10.0.0.5/nato/;
    }
    return $ip;
}


sub get_ip
{
   join ', ', grep $_ ne '',
       ($ENV{HTTP_X_FORWARDED_FOR} || ''), ($ENV{REMOTE_ADDR} || '');
}


sub local_ip { $_[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/ ? $1 == 10 || $1 == 192 && $2 == 168 : 1; }

sub linkify_ip
{
    my ($ip) = $_[0] || '';
    my (@ips) = split /[,\s]+/, $ip;
    my $short = (first { !local_ip($_) } @ips) || $ips[0] || '';
    (
        last_ip_short => $short,
        last_ip => (@ips > 1 ? $ip : ''),
        $short ? (href_whois => "http://whois.domaintools.com/$short") : (),
    )
}

1;
