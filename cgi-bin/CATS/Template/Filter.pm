package CATS::Template::Filter;

use strict;
use warnings;

use Template::Filters;

# Make control characters "printable", using character escape codes (CEC)
sub quot_cec
{
    my $cntrl = shift;
    my %es = ( # character escape codes, aka escape sequences
        # TODO: Process \t specially.
        "\t" => undef, #'\t',   # tab            (HT)
        "\n" => '\n',   # line feed      (LF)
        # TODO: Control EOL at git level.
        "\r" => undef, #'\r',   # carrige return (CR)
        "\f" => '\f',   # form feed      (FF)
        "\b" => '\b',   # backspace      (BS)
        "\a" => '\a',   # alarm (bell)   (BEL)
        "\e" => '\e',   # escape         (ESC)
        "\013" => '\v', # vertical tab   (VT)
        "\000" => '\0', # nul character  (NUL)
    );
    my $chr = exists $es{$cntrl}
            ? $es{$cntrl}
            : sprintf('\%02X', ord($cntrl));

    return $chr ? "<span class=\"cntrl\">$chr</span>" : '';
}

sub quote_controls_filter
{
    my $str = shift;

    $str =~ s/ /&nbsp;/g;
    $str =~ s|([[:cntrl:]])|quot_cec($1)|eg;
    return $str;
}

sub esc { quote_controls_filter(Template::Filters::html_filter($_[0])) }

# Highlight selected fragments of string, using given CSS class,
# and escape HTML.  It is assumed that fragments do not overlap.
# Regions are passed as list of pairs (array references).
#
# Example: [% 'foobar' | html_highlight_regions('mark', [ 0, 3 ]) %] returns
# '<span class="mark">foo</span>bar'
sub html_highlight_regions_filter
{
    my ($context, $css_class, @sel) = @_;
    @sel = grep { ref($_) eq 'ARRAY' } @sel;
    sub {
        my ($str) = @_;
        @sel or return esc($str);

        my $out = '';
        my $pos = 0;

        for my $s (@sel) {
            my ($begin, $end) = @$s;

            # Don't create empty <span> elements.
            next if $end <= $begin;

            my $escaped = esc(substr $str, $begin, $end - $begin);

            $out .= esc(substr $str, $pos, $begin - $pos) if $begin > $pos;
            $out .= sprintf '<span class="%s">%s</span>', $css_class, $escaped;

            $pos = $end;
        }
        $out .= esc(substr $str, $pos) if $pos < length $str;

        $out;
    }
}

# Replaces [http://url|text] with <a> tags. Apply after html filter.
sub linkify
{
    my ($s) = @_;
    $s =~ s~\[\s*((?:https?:/|\.)/[^\s|]+)(?:\s*\|\s*([^\]]+))?\s*\]~<a href="$1">@{[$2 || $1]}</a>~g;
    $s;
}

1;
