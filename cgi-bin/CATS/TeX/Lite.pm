package CATS::TeX::Lite;

use strict;
use warnings;

use List::Util qw(max);

use CATS::TeX::Data;

sub ss { "<span>@_</span>" }
sub sc { my $class = shift; qq~<span class="$class">@_</span>~ }

my %large_override_class = (int => 'int');

my $large_sym = sub {
    my $f = sc(($large_override_class{$_[0]} // 'large_sym'), $CATS::TeX::Data::large{$_[0]});
    sub { $f };
};
my $sqrt_sym = sc(sqrt_sym => '&#x221A;');

sub left_right {
    my ($text, $height) = @_;
    !$height || $height <= 1 ? $text :
    $height <= 4 ? sc("large hh$height", $text) :
    qq~<span class="large" style="transform: scaleY($height);">$text</span>~;
}

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
    underset => sub { sc(limits => sc(mid => ss($_[1])) . sc(lo => ss($_[0]))) },
    subsup => sub { sc('tbl hilo', ss(ss($_[0])) . ss(ss($_[1]))) },
    block  => sub { join '', @_ },
    'sqrt' => sub { ($_[1] ? qq~<sup class="root">$_[1]</sup>~ : '') . $sqrt_sym . sc(sqrt => $_[0]) },
    overline => sub { sc(over => @_) },
    accent_1 => sub { "$_[0]&#$_[1];" },
    accent_large => sub { sc(accent => ss($_[1]) . $_[0]) },
    frac   => sub { sc('frac sfrac', sc(nom => ss($_[0])) . ss(ss($_[1]))) },
    dfrac  => sub { sc('frac dfrac', sc(nom => ss($_[0])) . ss(ss($_[1]))) },
    space  => sub { '&nbsp;' },
    left   => \&left_right,
    right  => \&left_right,
    big    => sub { sc("large" => @_) },
    Big    => sub { sc("large hh2" => @_) },
    bigg   => sub { sc("large hh3" => @_) },
    Bigg   => sub { sc("large hh4" => @_) },
    boldsymbol => sub { sc(b => @_) },
    mathcal=> sub { sc(mathcal => @_) },
    texttt => sub { sc(tt => @_) },
    mbox   => \&ss,
    mathbb => sub { sc(mathbb => @_) },
    mathbf => sub { sc(b => @_) },
    mathop => \&ss,
    mathrm => sub { sc(mathrm => @_) },
    operatorname => sub { sc(mathrm => @_) },
    array  => sub { sc(array => sc("tbl $_[0]" => join '', @_[1..$#_])) },
    cell   => sub { '</span><span>' },
    row    => sub { ss(ss(@_)) },
    prime  => sub { length($_[0]) == 2 ? '&#8243;' : '&prime;' x length($_[0]) },
    map { $_ => $large_sym->($_) } keys %CATS::TeX::Data::large,
);

my $high_gens = { limits => 1, underset => 1 };

my $source;

sub sp { $_[0] eq '' ? '&#8239;' : '&nbsp;' }

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
        s/^\\%/%/;
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
    big => 1, Big => 1, bigg => 1, Bigg => 1,
    boldsymbol => 1,
    dfrac => 2,
    frac => 2,
    left => 1,
    mathbb => 1,
    mathbf => 1,
    mathcal => 1,
    mathop => 1,
    mathrm => 1,
    operatorname => 1,
    overline => 1,
    right => 1,
    underset => 2,
    map { $_ => 0 } keys %CATS::TeX::Data::large,
);

sub parse_optional {
    $source =~ s/^\[// or return ();
    my @optional = parse_token;
    $source =~ s/^]//;
    @optional;
}

sub _is_token { ref $_[0] eq 'ARRAY' && $_[0]->[0] eq $_[1] }

sub _token_as {
    my ($token, $type, $len) = @_;
    ref $token eq 'ARRAY' && @$token == 2 && $token->[0] eq $type ? $token->[1] : undef;
}

sub parse_block {
    my @res = ();
    my $limits = '';
    while ($source ne '') {
        last if $source =~ s/^\s*(?:\\end\{[a-zA-Z]+)?}//;
        if ($source =~ s/^(\s*)\\([_^])//) {
            push @res, [ op => '', $2, '' ];
        }
        elsif ($source =~ s/^\s*([_^])//) {
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
            elsif ($f eq 'sqrt') {
                my @optional = parse_optional;
                push @res, [ 'sqrt' => parse_token, @optional ];
            }
            elsif ($f eq 'texttt') {
                $source =~ s/^{([^{]*)}//;
                push @res, [ texttt => $1 ];
            }
            elsif ($f eq 'mbox') {
                $source =~ s/^{([^{]*)}//;
                push @res, [ mbox => $1 ];
            }
            elsif ($f eq 'over') {
                my $d = [ frac => $res[-1] // '', parse_token() ];
                @res ? ($res[-1] = $d) : push @res, $d;
            }
            elsif (my $accent = $CATS::TeX::Data::accents{$f}) {
                # Single-character accent via Unicode combining.
                my $arg = parse_token;
                my $block = _token_as($arg, 'block');
                my $var = $block && _token_as($block, 'var') || _token_as($arg, 'var');
                push @res, $var && length($var) == 1 ?
                    [ var => [ accent_1 => $var, $accent->[0] ] ] :
                    [ accent_large => $arg, $accent->[1] ];
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
                        $source =~ s/^\{([a-zA-Z]+)\}\s*//;
                        my $cols = join ' ', map substr($1, $_ - 1, 1) . $_, 1 .. length($1);
                        my @rows = ([ 'row', [ 'block' ] ]);
                        my (undef, @content) = @{parse_block()};
                        for (@content) {
                            if (_is_token($_, 'row')) {
                                push @rows, [ 'row', [ 'block' ] ];
                            }
                            else {
                                push @{$rows[-1]->[-1]}, $_;
                            }
                        }
                        push @res, [ array => $cols // '', @rows ];
                    }
                    else {
                        # Unknown environment, ignore.
                        push @res, parse_block();
                    }
                }
            }
            elsif ($f eq 'not' && $source =~ s/^\\([a-zA-Z]+)(\s*)//) {
                ($f, $rsp) = ($1, $2);
                push @res, make_token($lsp, "not_$f", $rsp);
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
        elsif ($source =~ s/^(\s*)~(\s*)//) {
            push @res, [ space => '~' ],
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
    my $parsed = parse_block();
    update_height($parsed);
    $parsed;
}

sub _set_height {
    my ($left, $height) = @_;
    $left->[2] = $height;
}

sub update_height {
    my ($tree) = @_;
    ref $tree eq 'ARRAY' or return 1;
    my ($name, @args) = @$tree;
    $name or return 1;
    if ($name eq 'block') {
        my $max = 0;
        my @stack;
        for my $el (@args) {
            if (_is_token($el, 'left')) {
                push @stack, [ $el, 1 ];
            }
            elsif (_is_token($el, 'right')) {
                $el->[2] = @stack ? _set_height(@{pop @stack}) : $max; # Maybe unopened \right.
            }
            else {
                my $cur = update_height($el);
                $_->[1] = max($_->[1], $cur) for @stack;
                $max = max($max, $cur);
            }
        }
        _set_height(@$_) for @stack; # Unclosed \left.
        return $max;
    }
    elsif ($name =~ /^(frac|dfrac)$/) {
        return update_height($args[0]) + update_height($args[1]);
    }
    elsif ($name eq 'array') {
        my $sum = 0;
        $sum += update_height($_) for @args[1..$#args];
        return $sum;
    }
    else {
        return ($high_gens->{$name} ? 1 : 0) + (@args ? update_height($args[0]) : 1);
    }
}

sub as_html {
    my ($tree) = @_;
    ref $tree eq 'ARRAY' or return $tree;
    my $name = shift @$tree;
    $name or return '???';
    my $prev = 0;
    # Insert space between directly adjacent variables.
    if ($name eq 'block') {
        for (@$tree) {
            my $cur = ref $_ eq 'ARRAY' && $_->[0] =~ /^(var|sub|sup)$/;
            push @$_, ' ' if $prev && $cur;
            $prev = $cur;
        }
    }
    my @html_params = map { as_html($_) } @$tree;
    $generators{$name} or die $name;
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
