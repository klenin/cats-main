package CATS::Redirect;

use strict;
use warnings;

use MIME::Base64;
use Storable qw();

sub encode { encode_base64(Storable::nfreeze($_[0]), '') }

sub pack_params {
    my ($p) = @_;
    my %params =
        map { +$_ => $p->web_param($_) }
        grep !($_ eq 'sid' || $p->has_upload($_)),
        $p->web_param_names;
    $params{f} //= $p->{f} if $p->{f}; # New url format.
    encode \%params;
}

sub unpack_params {
    my ($redir) = @_;
    $redir or return ();
    my $params = eval { Storable::thaw(decode_base64($redir)) };
    defined $params and return %$params;
    warn "Unable to decode redir '$redir'";
    return ();
}

1;
