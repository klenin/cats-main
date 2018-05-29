package CATS::Proxy;

use JSON::XS;
use LWP::UserAgent;

use CATS::Config;

my @whitelist = qw(
    www.codechef.com
    judge.u-aizu.ac.jp
    compprog.win.tue.nl
    stats.ioinformatics.org
    scoreboard.ioinformatics.org
    rosoi.net
);

sub proxy {
    my ($p, $url) = @_;
    my $r = join '|', map "\Q$_\E", @whitelist;
    ($url // '') =~ m[^http(s?)://($r)/] or die;
    my $is_https = $1;

    my $ua = LWP::UserAgent->new;
    # Workaround for LWP bug with https proxies, see http://www.perlmonks.org/?node_id=1028125
    # Use postfix 'if' to avoid trapping 'local' inside a block.
    local $ENV{https_proxy} = $CATS::Config::proxy if $CATS::Config::proxy;
    $ua->proxy($is_https ? (https => undef) : (http => "http://$CATS::Config::proxy")) if $CATS::Config::proxy;
    my $res = $ua->request(HTTP::Request->new(GET => $url, [ 'Accept', '*/*' ]));
    $res->is_success or die sprintf 'proxy http error: url=%s result=%s', $url, $res->status_line;

    if ($p->{jsonp}) {
        $p->content_type('application/json');
        $p->print("$p->{jsonp}(" . encode_json({ result => $res->content }) . ')');
    }
    else {
        $p->content_type('text/plain');
        $p->print($res->content);
    }
    $p->get_return_code;
}

1;
