use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 20;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::TeX::Lite;

sub tex { CATS::TeX::Lite::as_html(CATS::TeX::Lite::parse($_[0])) }

sub is_ { is tex($_[0]), $_[1], "tex $_[0]" }

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
is_ 'a^22', '<i>a</i><sup><span class="num">22</span></sup>'; # Non-compliant.
is_ 'a^{22}', '<i>a</i><sup><span class="num">22</span></sup>';
is_ 'a_{b+c}', '<i>a</i><sub><i>b</i>+<i>c</i></sub>';
is_ '\overline S', '<span class="over"><i>S</i></span>';
is_ '\frac 1 a',
    '<table class="frac sfrac">' .
    '<tr class="nom"><td><span class="num">1</span></td></tr>' .
    '<tr><td><i>a</i></td></tr>' .
    '</table>';
is_ '1 \over a',
    '<table class="frac sfrac">' .
    '<tr class="nom"><td><span class="num">1</span></td></tr>' .
    '<tr><td><i>a</i></td></tr>' .
    '</table>';
is_ '\dfrac{1}{a}',
    '<table class="frac dfrac">' .
    '<tr class="nom"><td><span class="num">1</span></td></tr>' .
    '<tr><td><i>a</i></td></tr>' .
    '</table>';

is_ '_5', '<sub><span class="num">5</span></sub>';
is_ '\over x',
    '<table class="frac sfrac">' .
    '<tr class="nom"><td></td></tr>' .
    '<tr><td><i>x</i></td></tr>' .
    '</table>';
