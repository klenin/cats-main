package CATS::IP;
use strict;
use warnings;

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


sub short_long
{
    my ($ip) = $_[0] || '';
    my ($short, @rest) = split /[,\s]+/, $ip;
    my $long = @rest ? $ip : '';
    ($short, $long);
}

1;
