package CATS::Web;

use warnings;
use strict;

use Apache2::Const -compile => qw(OK REDIRECT NOT_FOUND FORBIDDEN);
use Apache2::Cookie ();
use Apache2::Request;
use Apache2::Upload;
use Encode;

use 5.010;

my $r;
my $jar;
my $qq;
my $return_code;

sub new {
    my ($class, $self) = @_;
    bless $self // {}, $class;
}

sub init_request {
    my ($self, $apache_request) = @_;
    $r = $apache_request;
    $jar = Apache2::Cookie::Jar->new($r);
    $return_code = Apache2::Const::OK;
    $qq = Apache2::Request->new($r,
        POST_MAX => 10 * 1024 * 1024, # Actual limit is defined by Apache config.
        DISABLE_UPLOADS => 0);
}

sub print {
    my ($self, $data) = @_;
    $r->print($data);
}

sub print_json {
    my ($self, $data) = @_;
    $self->content_type('application/json');
    $self->print(JSON::XS->new->utf8->convert_blessed(1)->encode($data));
    -1;
}

sub get_uri { $r->uri }

sub web_param {
    if (wantarray) {
        map Encode::decode_utf8($_), $qq->param($_[1]);
    } else {
        Encode::decode_utf8($qq->param($_[1]));
    }
}

sub web_param_names { $qq->param }

sub has_upload { $qq->upload($_[1]) ? 1 : 0 }

sub get_return_code { $return_code }

sub redirect {
    my ($self, $location) = @_;
    $self->headers(Location => $location);
    $return_code = Apache2::Const::REDIRECT;
    -1;
}

sub not_found {
    $return_code = Apache2::Const::NOT_FOUND;
    -1;
}

sub forbidden {
    $return_code = Apache2::Const::FORBIDDEN;
    -1;
}

sub has_error { $return_code != Apache2::Const::OK }

sub headers {
    my ($self, @args) = @_;
    while (my ($header, $value) = splice @args, 0, 2) {
        if ($header eq 'cookie') {
            $r->err_headers_out->add('Set-Cookie' => $value->as_string) if $value;
        } else {
            $r->headers_out->set($header => $value);
        }
    }
}

sub content_type {
    my ($self, $mime, $enc) = @_;
    $r->content_type("${mime}" . ($enc ? "; charset=${enc}" : ''));
}

sub get_cookie {
    my ($self, $name) = @_;
    my $cookie = $jar->cookies(@_);
    $cookie ? $cookie->value : '';
}

sub make_cookie {
    my ($self, @rest) = @_;
    Apache2::Cookie->new($r, @rest);
}

sub user_agent { $r->headers_in->get('User-Agent') }
sub referer { $r->headers_in->get('Referer') }

sub log_info {
    my ($self, @rest) = @_;
    $r->log->notice(@rest);
}

# Params: { content_type, charset (opt), file_name, len (opt), content (must be encoded) }
sub print_file {
    my ($self, %p) = @_;
    $self->content_type($p{content_type}, $p{charset});
    $self->headers(
        'Accept-Ranges' => 'bytes',
        'Content-Length' => $p{len} // length($p{content}),
        'Content-Disposition' => "attachment; filename=$p{file_name}",
    );
    $self->print($p{content});
}

sub make_upload {
    my ($self, $name) = @_;
    my $u = $qq->upload($name) or return;
    CATS::Web::Upload->new({
        _name => $name, _upload => $u, _remote_file_name => $qq->param($name) });
}

package CATS::Web::Upload;

use warnings;
use strict;

sub new {
    my ($class, $self) = @_;
    bless $self, $class;
}

sub _ensure { $_[0]->{_upload} // die "Bad upload for parameter '$_[0]->{_name}'" }

sub remote_file_name { $_[0]->{_remote_file_name} }
sub local_file_name { $_[0]->_ensure->tempname }

sub content {
    $_[0]->_ensure->slurp(my $src = '');
    $src;
}

1;
