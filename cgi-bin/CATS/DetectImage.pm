package CATS::DetectImage;

use MIME::Base64;

my $headers = {
    jpeg => '\xFF.\xFF\xE0..JFIF\0',
    png => '\x89PNG', #\x0D\x0A\x1A',
    gif => 'GIF8[79]a',
    pdf => '%PDF-1\.5',
    # bmp => 'BM', # Too weak.
};

our $image_extension_re = qr/\.(?:jpe?g|png|gif|bmp|pdf)$/;

sub has_image_extension { $_[0] =~ $image_extension_re }

sub detect {
    my ($bytes) = @_;
    for my $name (keys %$headers) {
        my $re = $headers->{$name};
        return $name if $bytes =~ m/^$re/m;
    }
    undef;
}

sub add_image_data {
    my ($data, $field) = @_;
    my $format = detect($data->{$field}) or return;
    $data->{$field . '_image'} = { format => $format, base64 => encode_base64($data->{$field}) };
}

1;
