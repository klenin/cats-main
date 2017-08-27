use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 30;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::TeX::Lite;

sub tex { CATS::TeX::Lite::as_html(CATS::TeX::Lite::parse($_[0])) }

sub is_ {
    if (($ARGV[0] // '') eq 'gen') {
        print "<p>Text \$$_[0]\$ text></p>\n";
    }
    else {
        is tex($_[0]), $_[1], "tex $_[0]";
    }
}

is_ '1', '<span class="num">1</span>';
is_ 'a', '<i>a</i>';
is_ 'abc+def', '<i>abc</i>+<i>def</i>';
is_ 'a-b', '<i>a</i>&minus;<i>b</i>';
is_ 'a \le b', '<i>a</i>&nbsp;&le;&nbsp;<i>b</i>';

is_ 'a b c', '<i>a</i> <i>b</i> <i>c</i>';
is_ 'a b+c', '<i>a</i> <i>b</i>+<i>c</i>';
is_ 'f(b+c)', '<i>f</i>(<i>b</i>+<i>c</i>)';
is_ 'a,b,  c, d', '<i>a</i>,<i>b</i>, <i>c</i>, <i>d</i>';

is_ 'a_i', '<i>a</i><sub><i>i</i></sub>';
is_ 'a^2', '<i>a</i><sup><span class="num">2</span></sup>';
# Non-compliant, TeX gives a^{2}2.
is_ 'a^22', '<i>a</i><sup><span class="num">22</span></sup>';

is_ 'a^{22}', '<i>a</i><sup><span class="num">22</span></sup>';
is_ 'a_{b+c}', '<i>a</i><sub><i>b</i>+<i>c</i></sub>';
is_ '\overline S', '<span class="over"><i>S</i></span>';
is_ '\frac 1 a',
    '<span class="frac sfrac">' .
    '<span class="nom"><span><span class="num">1</span></span></span>' .
    '<span><span><i>a</i></span></span>' .
    '</span>';
is_ '\frac {x}  {y+z}',
    '<span class="frac sfrac">' .
    '<span class="nom"><span><i>x</i></span></span>' .
    '<span><span><i>y</i>+<i>z</i></span></span>' .
    '</span>';
is_ '1 \over a',
    '<span class="frac sfrac">' .
    '<span class="nom"><span><span class="num">1</span></span></span>' .
    '<span><span><i>a</i></span></span>' .
    '</span>';
is_ '\dfrac{1}{a}',
    '<span class="frac dfrac">' .
    '<span class="nom"><span><span class="num">1</span></span></span>' .
    '<span><span><i>a</i></span></span>' .
    '</span>';

is_ '_5', '<sub><span class="num">5</span></sub>';
is_ '\over x',
    '<span class="frac sfrac">' .
    '<span class="nom"><span></span></span>' .
    '<span><span><i>x</i></span></span>' .
    '</span>';

# Non-compliant, TeX gives error.
is_ 'x_a_b', '<i>x</i><sub><i>a</i></sub><sub><i>b</i></sub>';

is_ 'x_{a_b}', '<i>x</i><sub><i>a</i><sub><i>b</i></sub></sub>';

is_ '\max\limits_a^b',
    '<span class="limits hh">' .
    '<span class="hi"><span><i>b</i></span></span>' .
    '<span class="mid"><span><b>max</b></span></span>' .
    '<span class="lo"><span><i>a</i></span></span>' .
    '</span>';
is_ 'S\limits_{i+1} + 1',
    '<span class="limits">' .
    '<span class="mid"><span><i>S</i></span></span>' .
    '<span class="lo"><span><i>i</i>+<span class="num">1</span></span></span>' .
    '</span>&nbsp;+&nbsp;<span class="num">1</span>';

is_ '\sqrt{\overline Q} + \sqrt \alpha',
    '<span class="sqrt_sym">&#x221A;</span><span class="sqrt"><span class="over"><i>Q</i></span></span>' .
    '&nbsp;+&nbsp;<span class="sqrt_sym">&#x221A;</span><span class="sqrt">&alpha;</span>';

is_ 'a\leftarrow b\rightarrow c', '<i>a</i>&larr;&nbsp;<i>b</i>&rarr;&nbsp;<i>c</i>';
is_ '\left((a)\right)', '<span class="large">(</span>(<i>a</i>)<span class="large">)</span>';

is_ 'a \mod b \bmod c', '<i>a</i>&nbsp;<b>mod</b>&nbsp;<i>b</i>&nbsp;<b>mod</b>&nbsp;<i>c</i>';

is_ '\int\sum\prod',
    '<span class="int">&int;</span><span class="large_sym">&sum;</span><span class="large_sym">&prod;</span>';
