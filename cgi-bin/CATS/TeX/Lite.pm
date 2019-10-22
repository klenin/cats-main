package CATS::TeX::Lite;

use strict;
use warnings;

use CATS::TeX::Data;

sub ss { "<span>@_</span>" }
sub sc { my $class = shift; qq~<span class="$class">@_</span>~ }

my $large_sym = sub { my $f = sc(($_[1] // 'large_sym'), $CATS::TeX::Data::symbols{$_[0]}); sub { $f }; };

my %generators = (
    var    => sub { ($_[1] || '') . "<i>$_[0]</i>" },
    num    => sub { ($_[1] || '') . sc(num => $_[0]) },
    op     => sub { join '', @_ },
    spec   => sub {
        join '', map { $CATS::TeX::Data::symbols{$_} || $_ && $_ ne '&nbsp;' && "<b>$_</b>" || $_ } @_ },
    sup    => sub { qq~<sup>$_[0]</sup>~ },
    'sub'  => sub { qq~<sub>$_[0]</sub>~ },
    # We wish to align to baseline of the middle row, but CSS calculates baseline only from first row.
    # So use baseline when there is no upper limit and middle otherwise.
    limits => sub { sc('limits' . ($_[1] ? ' hh' : '') =>
        ($_[1] ? sc(hi => ss($_[1])) : '') . sc(mid => ss($_[0])) . ($_[2] ? sc(lo => ss($_[2])) : '')
    ) },
    subsup => sub { sc('tbl hilo', ss(ss($_[0])) . ss(ss($_[1]))) },
    block  => sub { join '', @_ },
    'sqrt' => sub { sc(sqrt_sym => '&#x221A;') . sc(sqrt => @_) },
    overline => sub { sc(over => @_) },
    frac   => sub { sc('frac sfrac', sc(nom => ss($_[0]))  . ss(ss($_[1]))) },
    dfrac  => sub { sc('frac dfrac', sc(nom => ss($_[0]))  . ss(ss($_[1]))) },
    space  => sub { '&nbsp;' },
    left   => sub { sc(large => @_) },
    right  => sub { sc(large => @_) },
    mathcal=> sub { sc(mathcal => @_) },
    sum    => $large_sym->('sum'),
    prod   => $large_sym->('prod'),
    int    => $large_sym->('int', 'int'),
    array  => sub { sc(tbl => ss(ss($_[1]))) },
    cell   => sub { '</span><span>' },
    row    => sub { '</span></span><span><span>' },
    prime  => sub { length($_[0]) == 2 ? '&#8243;' : '&prime;' x length($_[0]) },
);

my $source;

sub sp { $_[0] eq '' ? '' : '&nbsp;' }

sub is_binop { exists $CATS::TeX::Data::binary{$_[0]} }

sub make_token { [ spec => (is_binop($_[1]) ?
    (sp($_[0]), $_[1], sp($_[2])) :
    ('', $_[1],  ($_[2] eq '' ? '' : ' '))
)] }

sub parse_token {
    for ($source) {
        # Translate spaces about operations to &nbsp;.
        s/^(\s*)-(\s*)// && return [ op => sp($1), '&minus;', sp($2) ];
        s/^(\s*)([+*\/><=])(\s*)// && return [ op => sp($1), $2, sp($3) ];
        s/^(\s*)\\([a-zA-Z]+|\{|\})(\s*)// && return make_token($1, $2, $3);
        s/^\s*//;
        s/^\\(,|;|\s+)// && return [ space => $1 ];
        s/^([()\[\]])// && return [ op => $1 ];
        s/^([a-zA-Z]+)// && return [ var => $1 ];
        s/^([0-9]+(:?\.[0-9]+)?)// && return [ num => $1 ];
        # Single space after punctuation.
        s/^([.,:;])(\s*)// && return [ op => $1, ($2 eq '' ? '' : ' ') ];
        s/^{// && return parse_block();
        s/^('+)// && return [ prime => $1 ];
        s/^(\S)// && return [ op => $1 ];
    }
}

my %simple_commands = (
    dfrac => 2,
    frac => 2,
    int => 0,
    left => 1,
    mathcal => 1,
    overline => 1,
    prod => 0,
    right => 1,
    'sqrt' => 1,
    sum => 0,
);

sub parse_block {
    my @res = ();
    my $limits = '';
    while ($source ne '') {
        last if $source =~ s/^\s*(?:\\end\{[a-zA-Z]+)?}//;
        if ($source =~ s/^\s*([_^])//) {
            my $f = $1 eq '_' ? 'sub' : 'sup';
            if (@res && $res[-1]->[0] eq 'limits') {
                $res[-1]->[$f eq 'sup' ? 2 : 3] = parse_token;
            }
            elsif (@res && $res[-1]->[0] eq ($f eq 'sub' ? 'sup' : 'sub')) {
                $res[-1] = [ subsup => ($f eq 'sub' ?
                    ($res[-1]->[1], parse_token()) :
                    (parse_token(), $res[-1]->[1])) ];
            }
            else {
                push @res, [ $f, parse_token() ];
            }
        }
        elsif ($source =~ s/^(\s*)\\([a-zA-Z]+)(\s*)//) {
            my ($lsp, $f, $rsp) = ($1, $2, $3);
            if (defined(my $args_count = $simple_commands{$f})) {
                push @res, [ $f, map parse_token, 1 .. $args_count ]
            }
            elsif ($f eq 'over') {
                my $d = [ frac => $res[-1] // '', parse_token() ];
                @res ? ($res[-1] = $d) : push @res, $d;
            }
            elsif ($f eq 'limits') {
                $res[-1] ? $res[-1] = [ limits => $res[-1] ] : push @res, [ limits => '' ];
            }
            elsif ($f eq 'displaystyle') { # Ignore.
            }
            elsif ($f eq 'bmod' || $f eq 'mod') {
                push @res, [ spec => sp($lsp), 'mod', sp($rsp) ];
            }
            elsif ($f eq 'begin') {
                if ($source =~ s/^\{([a-zA-Z]+)\}\s*//) {
                    my $env= $1;
                    if ($env eq 'array') {
                        my ($cols) = $source =~ s/^\{([a-zA-Z]+)\}\s*//;
                        push @res, [ array => $cols // '', parse_block() ];
                    }
                    else {
                        # Unknown environment, ignore.
                        push @res, parse_block();
                    }
                }
            }
            else {
                push @res, make_token($lsp, $f, $rsp);
            }
        }
        elsif ($source =~ s/^(\s*)\&(\s*)//) {
            push @res, [ 'cell' ],
        }
        elsif ($source =~ s/^(\s*)\\\\(\s*)//) {
            push @res, [ 'row' ],
        }
        else {
            push @res, parse_token();
        }
    }
    return [ block => @res ];
}

sub parse {
    ($source) = @_;
    $source =~ s/\n|\r/ /g;
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
