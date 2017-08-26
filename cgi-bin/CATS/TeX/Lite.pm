package CATS::TeX::Lite;

use strict;
use warnings;

use CATS::TeX::Data;

my %generators = (
    var    => sub { ($_[1] || '') . "<i>$_[0]</i>" },
    num    => sub { ($_[1] || '') . qq~<span class="num">$_[0]</span>~ },
    op     => sub { join '', @_ },
    spec   => sub {
        join '', map { $CATS::TeX::Data::symbols{$_} || $_ && $_ ne '&nbsp;' && "<b>$_</b>" || $_ } @_ },
    sup    => sub { qq~<sup>$_[0]</sup>~ },
    'sub'  => sub { qq~<sub>$_[0]</sub>~ },
    sub1   => sub { qq~<table class="limits"><tr><td>$_[0]</td></tr><tr><td class="sub">$_[1]</td></tr></table>~ },
    sup1   => sub { qq~<table class="limits"><tr><td class="sup">$_[1]</td></tr><tr><td>$_[0]</td></tr></table>~ },
    block  => sub { join '', @_ },
    'sqrt' => sub { qq~<span class="sqrt_sym">\&#x221A;</span><span class="sqrt">@_</span>~ },
    overline => sub { qq~<span class="over">@_</span>~ },
    frac   => sub { qq~<span class="frac sfrac"><span class="nom"><span>$_[0]</span></span><span><span>$_[1]</span></span></span>~ },
    dfrac  => sub { qq~<span class="frac dfrac"><span class="nom"><span>$_[0]</span></span><span><span>$_[1]</span></span></span>~ },
    space  => sub { '&nbsp;' }
);

my $source;

sub sp { $_[0] eq '' ? '' : '&nbsp;' }

sub is_binop { exists $CATS::TeX::Data::binary{$_[0]} }

sub parse_token {
    for ($source) {
        # Translate spaces about operations to &nbsp;.
        s/^(\s*)-(\s*)// && return [ op => sp($1), '&minus;', sp($2) ];
        s/^(\s*)([+*\/><=])(\s*)// && return [ op => sp($1), $2, sp($3) ];
        s/^(\s*)\\([a-zA-Z]+|\{|\})(\s*)// &&
            return [ spec => (is_binop($2) ? (sp($1), $2, sp($3)) : ('', $2,  ($3 eq '' ? '' : ' '))) ];
        s/^\s//;
        s/^\\(,|;|\s+)// && return [ space => $1 ];
        s/^([()\[\]])// && return [ op => $1 ];
        s/^([a-zA-Z]+)// && return [ var => $1 ];
        s/^([0-9]+(:?\.[0-9]+)?)// && return [ num => $1 ];
        # Single space after punctuation.
        s/^([.,:;])(\s*)// && return [ op => $1, ($2 eq '' ? '' : ' ') ];
        s/^{// && return parse_block();
        s/^(\S)// && return [ op => $1 ];
    }
}

sub parse_block {
    my @res = ();
    my $limits = '';
    while ($source ne '') {
        last if $source =~ s/^\s*}//;
        if ($source =~ s/^\s*([_^])//) {
            my $f = $1 eq '_' ? 'sub' : 'sup';
            
            if ($limits) {
                my $d = [ $f . '1', $res[-1] // '', parse_token() ];
                @res ? ($res[-1] = $d) : push @res, $d;
            }
            else {
                push @res, [ $f, parse_token() ];
            }
        }
        elsif ($source =~ s/^\s*(?:\\(sqrt|overline))//) {
            my $f = $1;
            push @res, [ $f, parse_token() ];
        }
        elsif ($source =~ s/^\s*(?:\\over)//) {
            my $d = [ frac => $res[-1] // '', parse_token() ];
            @res ? ($res[-1] = $d) : push @res, $d;
        }
        elsif ($source =~ s/^\s*(?:\\limits)//) {
            $limits = 1;
        }
        elsif ($source =~ s/^\s*(?:\\(d?frac))//) {
            my $f = $1;
            push @res, [ $f, parse_token(), parse_token() ];
        }
        else {
            push @res, parse_token();
        }
    }
    return [ block => @res ];
}

sub parse {
    ($source) = @_;
    return parse_block();
}

sub as_html {
    my ($tree) = @_;
    ref $tree eq 'ARRAY' or return $tree;
    my $name = shift @$tree;
    $name or return '???';
    my $prev = 0;
    # Insert space between directly adjacent variables and numbers.
    if ($name eq 'block') {
        for (@$tree) {
            my $cur = ref $_ eq 'ARRAY' && $_->[0] =~ /^(var|num|sub|sup)$/;
            push @$_, ' ' if $prev && $cur;
            $prev = $cur;
        }
    }
    my @html_params = map { as_html($_) } @$tree;
    $generators{$name}->(@html_params);
}

sub quote_attr {
    my ($attr) = $_[0];
    $attr =~ s/"/&quot;/g;
    $attr =~ s/&/&amp;/g;
    $attr;
}

sub convert_one {
    my ($tex) = @_;
    # Reverse Unicode characters to ASCII, allowing TeX to re-generate them properly.
    for ($tex) {
        s/\xA0/ /g; # Non-breaking space.
        s/[\x{2013}\x{2212}]/-/g; # En-dash, minus sign.
    }
    sprintf '<span class="TeX" title="%s">%s</span>', quote_attr($tex), as_html(parse($tex))
}

sub convert_all {
    $_[0] =~ s/(\$([^\$]*[^\$\\])\$)/convert_one($2)/eg;
}

sub styles() { '' }
1;
