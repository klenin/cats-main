package CATS::Web;

use warnings;
use strict;

use Apache2::Const -compile => qw(OK REDIRECT NOT_FOUND FORBIDDEN);
use Apache2::Cookie ();
use Apache2::Request;
use Apache2::Upload;

use 5.010;

use Exporter qw(import);
our @EXPORT_OK = qw(
    content_type
    cookie
    forbidden
    get_return_code
    has_error
    has_upload
    init_request
    log_info
    not_found
    param
    restore_parameters
    save_uploaded_file
    upload_source
    url_param
    user_agent
);

my $r;
my $jar;
my $qq;
my $return_code;

sub new {
    my ($class, $self) = @_;
    bless $self, $class;
}

sub init_request {
    $r = $_[0];
    $jar = Apache2::Cookie::Jar->new($r);
    $return_code = Apache2::Const::OK;
    $qq = Apache2::Request->new($r,
        POST_MAX => 10 * 1024 * 1024, # Actual limit is defined by Apache config.
        DISABLE_UPLOADS => 0);
    no warnings 'redefine';
    *_param = \&original_param;
}

sub print { $r->print($_[0]) }

sub print_json {
    my ($self, $data) = @_;
    content_type('application/json');
    CATS::Web::print(JSON::XS->new->utf8->convert_blessed(1)->encode($data));
    -1;
}

sub get_uri { $r->uri }

sub original_param { $qq->param(@_) }

*_param = \&original_param;

# Trick to change param implementation at runtime.
sub param { _param(@_) }
*url_param = \&param;

sub ensure_upload { $qq->upload($_[0]) // die "Bad upload for parameter '$_[0]'" }

sub has_upload { $qq->upload($_[0]) ? 1 : 0 }

sub save_uploaded_file { ensure_upload($_[0])->tempname }

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
    my ($mime, $enc) = @_;
    $r->content_type("${mime}" . ($enc ? "; charset=${enc}" : ''));
}

sub cookie {
    if (@_ == 1) {
        my $cookie = $jar->cookies(@_);
        return $cookie ? $cookie->value() : '';
    } else {
        return Apache2::Cookie->new($r, @_);
    }
}

sub upload_source {
    my $src = '';
    ensure_upload($_[0])->slurp($src);
    $src;
}

sub restore_parameters {
    my $params = $_[0];
    no warnings 'redefine';
    *_param = sub {
        if (@_ == 1) {
            return $params->{$_[0]} || original_param(@_);
        }
        original_param(@_);
    }
}

sub user_agent { $r->headers_in->get('User-Agent') }

sub log_info { $r->log->notice(@_) }

# Params: { content_type, charset (opt), file_name, len (opt), content (must be encoded) }
sub print_file {
    my ($self, %p) = @_;
    content_type($p{content_type}, $p{charset});
    $self->headers(
        'Accept-Ranges' => 'bytes',
        'Content-Length' => $p{len} // length($p{content}),
        'Content-Disposition' => "attachment; filename=$p{file_name}",
    );
    CATS::Web::print($p{content});
}

1;
