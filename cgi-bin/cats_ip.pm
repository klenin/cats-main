package cats_ip;

sub filter_ip
{
    my ($ip) = @_;
    defined $ip or return;
    for ($ip)
    {
        s/195.209.254.222/pin/;
        s/195.209.254.4/www/;
        s/195.209.254.3/proxy/;
        s/192.168.1.5/nato/;
    }
    return $ip;
}


sub get_ip
{
   join ', ', grep $_ ne '',
       ($ENV{HTTP_X_FORWARDED_FOR} || ''), ($ENV{REMOTE_ADDR} || '');
}

1;
