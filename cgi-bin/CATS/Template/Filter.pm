package CATS::Template::Filter;

use strict;
use warnings;

# Make control characters "printable", using character escape codes (CEC)
sub quot_cec
{
    my $cntrl = shift;
    my %es = ( # character escape codes, aka escape sequences
        "\t" => '\t',   # tab            (HT)
        "\n" => '\n',   # line feed      (LF)
        "\r" => '\r',   # carrige return (CR)
        "\f" => '\f',   # form feed      (FF)
        "\b" => '\b',   # backspace      (BS)
        "\a" => '\a',   # alarm (bell)   (BEL)
        "\e" => '\e',   # escape         (ESC)
        "\013" => '\v', # vertical tab   (VT)
        "\000" => '\0', # nul character  (NUL)
    );
    my $chr = exists $es{$cntrl}
            ? $es{$cntrl}
            : sprintf('\%2x', ord($cntrl));

    return "<span class=\"cntrl\">$chr</span>";
}

sub quote_controls_filter
{
    my $str = shift;

    $str =~ s/ /&nbsp;/g;
    $str =~ s|([[:cntrl:]])|quot_cec($1)|eg;
    return $str;
}

1;
