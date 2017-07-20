package CATS::Redirect;

use strict;
use warnings;

use MIME::Base64;
use Storable qw();

use CATS::Web qw(url_param);

sub pack_params {
    encode_base64(Storable::nfreeze
        { map { $_ ne 'sid' ? ($_ => url_param($_)) : () } url_param })
}

sub unpack_params {
    my ($redir) = @_;
    $redir or return ();
    my $params = Storable::thaw(decode_base64($redir));
    defined $params and return %$params;
    warn "Unable to decode redir '$redir'";
    return ();
}

1;
