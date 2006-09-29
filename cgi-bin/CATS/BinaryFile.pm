package CATS::BinaryFile;

use strict;
use warnings;

sub load
{
    my ($fname, $result) = @_;
    open my $fh, "<$fname" or return 0;
    binmode($fh, ':raw');

    $$result = '';
    while (sysread($fh, my $buffer, 8192))
    {
        $result .= $buffer;
    }
    close $fh;
    1;
}


1;
