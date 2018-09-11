package CATS::Redirect;

use strict;
use warnings;

use MIME::Base64;
use Storable qw();

sub pack_params {
    my ($p) = @_;
    my $params = {
        map { $_ eq 'sid' || $p->has_upload($_) ? () : ($_ => $p->web_param($_)) } $p->web_param_names };
    encode_base64(Storable::nfreeze($params), '');
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
