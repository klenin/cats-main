package CATS::BinaryFile;

use strict;
use warnings;

use Carp;

sub load
{
    my ($fname, $result, %p) = @_;
    ref $result eq 'SCALAR' or die;

    open my $fh, '<', $fname or die "$fname not found";
    binmode($fh, ':raw');

    $$result = '';
    while (sysread($fh, my $buffer, 8192))
    {
        $$result .= $buffer;
    }
    close $fh;
    1;
}


sub save
{
    my ($fname, $data) = @_;
    $data or croak 'No data';
    open my $fh, '>', $fname or die "Can not write to $fname";
    binmode($fh);
    syswrite($fh, $data, length($data));
    close $fh;
}


1;
