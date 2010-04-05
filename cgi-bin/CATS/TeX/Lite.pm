package CATS::TeX::Lite;

use lib '../..';
use strict;
use warnings;

use CATS::TeX::TeXData;

my %generators = (
    var    => sub { ($_[1] || '') . "<i>$_[0]</i>" },
    num    => sub { ($_[1] || '') . qq~<span class="num">$_[0]</span>~ },
    op     => sub { join '', @_ },
    spec   => sub { join '', map { $CATS::TeX::TeXData::symbols{$_} || $_ && "<b>$_</b>" || $_ } @_ },
    sup    => sub { qq~<sup>$_[0]</sup>~ },
    'sub'  => sub { qq~<sub>$_[0]</sub>~ },
    sub1   => sub { qq~<table class="limits"><tr><td>$_[0]</td></tr><tr><td class="sub">$_[1]</td></tr></table>~ },
    sup1   => sub { qq~<table class="limits"><tr><td class="sup">$_[1]</td></tr><tr><td>$_[0]</td></tr></table>~ },
    block  => sub { join '', @_ },
    'sqrt' => sub { qq~<span class="sqrt_sym">\&#x221A;</span><span class="sqrt">@_</span>~ },
    over   => sub { qq~<span class="over">@_</span>~ },
    frac   => sub { qq~<table class="frac"><tr class="nom"><td>$_[0]</td></tr><tr><td>$_[1]</td></tr></table>~ },
    space  => sub { '&nbsp;' }
);

my $source;


sub sp { $_[0] eq '' ? '' : '&nbsp;' }

sub is_binop { exists $CATS::TeX::TeXData::binary{$_[0]} }


sub parse_token
{
    for ($source)
    {
        # пробелы вокруг операций превращаются в &nbsp;
        s/^(\s*)-(\s*)// && return ['op', sp($1), '&minus;', sp($2)];
        s/^(\s*)([+*\/><=])(\s*)// && return ['op', sp($1), $2, sp($3)];
        s/^(\s*)\\([a-zA-Z]+)(\s*)// &&
            return ['spec', (is_binop($2) ? (sp($1), $2, sp($3)) : ('', $2,  ($3 eq '' ? '' : ' ')))];
        s/^\s*//;
        s/^\\(,|;)// && return ['space', $1];
        s/^([()\[\]])// && return ['op', $1];
        s/^([a-zA-Z]+)// && return ['var', $1];
        s/^([0-9]+(:?\.[0-9]+)?)// && return ['num', $1];
        # один пробел после знаков препинания
        s/^([.,:;])(\s*)// && return ['op', $1, ($2 eq '' ? '' : ' ')];
        s/^{// && return parse_block();
        s/^(\S)// && return ['op', $1];
    }
}


sub parse_block
{
    my @res = ();
    my $limits = '';
    while ($source ne '')
    {
        last if $source =~ s/^\s*}//;
        if ($source =~ s/^\s*([_^])//)
        {
            @res or die '!';
            my $f = $1 eq '_' ? 'sub' : 'sup';
            
            if ($limits)
            {
                $res[-1] = [$f . '1', $res[-1], parse_token()];
            }
            else
            {
                push @res, [$f, parse_token()];
            }
        }
        elsif ($source =~ s/^\s*(?:\\(sqrt|over))//)
        {
            my $f = $1;
            push @res, [$f, parse_token()];
        }
        elsif ($source =~ s/^\s*(?:\\limits)//)
        {
            $limits = 1;
        }
        elsif ($source =~ s/^\s*(?:\\(frac))//)
        {
            my $f = $1;
            push @res, [$f, parse_token(), parse_token()];
        }
        else
        {
            push @res, parse_token();
        }
    }
    return ['block', @res];
}


sub parse
{
    ($source) = @_;
    return parse_block();
}


sub asHTML
{
    my ($tree) = @_;
    ref $tree eq 'ARRAY' or return $tree;
    my $name = shift @$tree;
    $name or return '???';
    my $prev = 0;
    # вставить пробелы между подряд идущими переменными и числами
    for (@$tree)
    {
        my $cur = ref $_ eq 'ARRAY' && $_->[0] =~ /^(var|num|sub|sup)$/;
        push @$_, ' ' if $prev && $cur;
        $prev = $cur;
    }
    my @html_params = map { asHTML($_) } @$tree;
    return $generators{$name}->(@html_params);
}


sub convert_one { '<span class="TeX">' . asHTML(parse($_[0])) . '</span>'; }


sub convert_all
{
    $_[0] =~ s/(\$([^\$]*[^\$\\])\$)/convert_one($2)/eg;
}


sub styles() { '' }


#print convert_one('a_1, a_2, \ldots , a_{n+1}');
#print convert_one('a + b+c');

1;
