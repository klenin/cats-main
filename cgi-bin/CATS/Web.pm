package CATS::Web;

use warnings;
use strict;
use Apache2::Request;
use Apache2::Upload;
use Apache2::Const -compile => qw(OK REDIRECT NOT_FOUND);
use Apache2::Cookie ();
use CATS::Utils qw(encodings);

use 5.010;

BEGIN {
    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT_OK = qw(
        init_request
        url_param
        param
        param_on
        encoding_param
        redirect
        headers
        get_return_code
        save_uploaded_file
        cookie
        content_type
        upload_source
        restore_parameters
        );
    our %EXPORT_TAGS = (all => [@EXPORT_OK]);
}


my $r;
my $jar;
my $qq;
my $return_code;


sub init_request
{
    $r = $_[0];
    $jar = Apache2::Cookie::Jar->new($r);
    $return_code = Apache2::Const::OK;
    $qq = Apache2::Request->new($r,
        POST_MAX => 10 * 1024 * 1024, # Actual limit is defined by Apache config.
        DISABLE_UPLOADS => 0);
    no warnings 'redefine';
    *_param = \&original_param;
}


sub original_param
{
    $qq->param(@_);
}

*_param = \&original_param;


sub encoding_param
{
    my $enc = param($_[0]) || '';
    encodings->{$enc} ? $enc : ($_[1] || 'UTF-8');
}


sub param
{
    _param(@_); # trick to change param implementation at runtime
}
*url_param = \&param;


sub param_on
{
    return (param($_[0]) || '') eq 'on';
}

sub ensure_upload { $qq->upload($_[0]) || die "Bad upload for parameter '$_[0]'" }

sub save_uploaded_file { ensure_upload($_[0])->tempname }

sub get_return_code { $return_code }


sub redirect
{
    my ($location,) = @_;
    headers(Location => $location);
    $return_code = Apache2::Const::REDIRECT;
    -1;
}

sub not_found
{
    $return_code = Apache2::Const::NOT_FOUND;
    -1;
}

sub headers
{
    while (my ($header, $value) = splice @_, 0, 2) {
        if ($header eq 'cookie') {
            $r->err_headers_out->add('Set-Cookie' => $value->as_string) if $value;
        } else {
            $r->headers_out->set($header => $value);
        }
    }
}


sub content_type
{
    my ($mime, $enc) = @_;
    $r->content_type("${mime}" . ($enc ? "; charset=${enc}" : ''));
}


sub cookie
{
    if (@_ == 1) {
        my $cookie = $jar->cookies(@_);
        return $cookie ? $cookie->value() : '';
    } else {
        return Apache2::Cookie->new($r, @_);
    }
}


sub upload_source
{
    my $src = '';
    ensure_upload($_[0])->slurp($src);
    $src;
}


sub restore_parameters
{
    my $params = $_[0];
    no warnings 'redefine';
    *_param = sub {
        if (@_ == 1) {
            return $params->{$_[0]} || original_param(@_);
        }
        original_param(@_);
    }
}


1;
