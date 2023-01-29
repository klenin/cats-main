use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 61;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::TeX::Lite;

sub tex { CATS::TeX::Lite::as_html(CATS::TeX::Lite::parse($_[0])) }
sub text_tex { CATS::TeX::Lite::convert_text($_[0]) }

sub is_ {
    if (($ARGV[0] // '') eq 'gen') {
        print "<p>Text \$$_[0]\$ text></p>\n";
    }
    else {
        is tex($_[0]), $_[1], "tex $_[0]";
    }
}

sub is_t {
    if (($ARGV[0] // '') eq 'gen') {
        print "<p>Text \$$_[0]\$ text></p>\n";
    }
    else {
        is text_tex($_[0]), $_[1], join ' ', 'tex', split "\n", $_[0];
    }
}

sub is_u {
    is CATS::TeX::Lite::update_height(CATS::TeX::Lite::parse($_[0])), $_[1], "height $_[0]";
}

is_ '1', '<span class="num">1</span>';
is_ 'a', '<i>a</i>';
is_ '2x', '<span class="num">2</span><i>x</i>';
is_ 'abc + def', '<i>abc</i>&nbsp;+&nbsp;<i>def</i>';
is_ 'a-b', '<i>a</i>&#8239;&minus;&#8239;<i>b</i>';
is_ 'a \le b', '<i>a</i>&nbsp;&le;&nbsp;<i>b</i>';
is_ 'a \texttt{c+1} b', '<i>a</i><span class="tt">c+1</span><i>b</i>';
is_ 'a \mbox{any text} b', '<i>a</i><span>any text</span><i>b</i>';
is_ '10\%', '<span class="num">10</span>%';

is_ 'a b c', '<i>a</i> <i>b</i> <i>c</i>';
is_ 'a b+c', '<i>a</i> <i>b</i>&#8239;+&#8239;<i>c</i>';
is_ 'f(b+c)', '<i>f</i>(<i>b</i>&#8239;+&#8239;<i>c</i>)';
is_ 'a,b,  c, d', '<i>a</i>,<i>b</i>, <i>c</i>, <i>d</i>';

is_ 'a_i', '<i>a</i><sub><i>i</i></sub>';
is_ 'a\_i', '<i>a</i>_<i>i</i>';
is_ 'a^2', '<i>a</i><sup><span class="num">2</span></sup>';
# Non-compliant, TeX gives a^{2}2.
is_ 'a^22', '<i>a</i><sup><span class="num">22</span></sup>';

is_ 'a^{22}', '<i>a</i><sup><span class="num">22</span></sup>';
is_ 'a_{b+c}', '<i>a</i><sub><i>b</i>&#8239;+&#8239;<i>c</i></sub>';
is_ 'a_{\mbox{bc}}', '<i>a</i><sub><span>bc</span></sub>';
is_ '\overline S', '<span class="over"><i>S</i></span>';
is_ '\frac 1 a',
    '<span class="frac sfrac">' .
    '<span class="nom"><span><span class="num">1</span></span></span>' .
    '<span><span><i>a</i></span></span>' .
    '</span>';
is_ '\frac {x}  {y+z}',
    '<span class="frac sfrac">' .
    '<span class="nom"><span><i>x</i></span></span>' .
    '<span><span><i>y</i>&#8239;+&#8239;<i>z</i></span></span>' .
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

{
my $hilo = '<i>x</i>' .
    '<span class="tbl hilo">' .
    '<span><span><i>a</i></span></span>' .
    '<span><span><i>b</i></span></span>' .
    '</span>';
is_ 'x^a_b', $hilo;
is_ 'x_b^a', $hilo;
}

is_ '\max\limits_a^b',
    '<span class="limits hh">' .
    '<span class="hi"><span><i>b</i></span></span>' .
    '<span class="mid"><span><b>max</b></span></span>' .
    '<span class="lo"><span><i>a</i></span></span>' .
    '</span>';
is_ 'S\limits_{i+1} + 1',
    '<span class="limits">' .
    '<span class="mid"><span><i>S</i></span></span>' .
    '<span class="lo"><span><i>i</i>&#8239;+&#8239;<span class="num">1</span></span></span>' .
    '</span>&nbsp;+&nbsp;<span class="num">1</span>';
is_ '\underset i X',
    '<span class="limits">' .
    '<span class="mid"><span><i>X</i></span></span>' .
    '<span class="lo"><span><i>i</i></span></span>' .
    '</span>';

is_ '\sqrt{\overline Q} + \sqrt \alpha',
    '<span class="sqrt_sym">&#x221A;</span><span class="sqrt"><span class="over"><i>Q</i></span></span>' .
    '&nbsp;+&nbsp;<span class="sqrt_sym">&#x221A;</span><span class="sqrt">&alpha;</span>';
is_ '\sqrt[3]{5}',
    '<sup class="root"><span class="num">3</span></sup><span class="sqrt_sym">&#x221A;</span>' .
    '<span class="sqrt"><span class="num">5</span></span>';

is_ 'a\leftarrow b\rightarrow c', '<i>a</i>&larr;&nbsp;<i>b</i>&rarr;&nbsp;<i>c</i>';
is_ '\left((a)\right)', '((<i>a</i>))';

is_ 'a \mod b \bmod c', '<i>a</i>&nbsp;<b>mod</b>&nbsp;<i>b</i>&nbsp;<b>mod</b>&nbsp;<i>c</i>';

is_ '\int\sum\prod\bigcup' =>
    '<span class="int">&int;</span>' .
    '<span class="large_sym">&sum;</span>' .
    '<span class="large_sym">&prod;</span>' .
    '<span class="large_sym">&#x22C3;</span>';

is_ 'a \not\equiv b', '<i>a</i>&nbsp;&nequiv;&nbsp;<i>b</i>';

is_ q~\begin{unknownenv}a\end{unknownenv}~, '<i>a</i>';

is_ q~\begin{array}{l}a\end{array}~,
    '<span class="array"><span class="tbl l1">' .
    '<span><span><i>a</i></span></span>' .
    '</span></span>';
is_ '\left\{\begin{array}{l}x\\\\y\end{array}',
    '<span class="large hh2">{</span>' .
    '<span class="array"><span class="tbl l1">' .
    '<span><span><i>x</i></span></span>' .
    '<span><span><i>y</i></span></span>' .
    '</span></span>';

is_ q~\begin{array}{lr}123&a \\\\ b & c\end{array}~,
    '<span class="array"><span class="tbl l1 r2">' .
    '<span><span><span class="num">123</span></span><span><i>a</i></span></span>' .
    '<span><span><i>b</i></span><span><i>c</i></span></span>' .
    '</span></span>';

is_ q~\begin{cases}x \\\\ y \end{cases}~,
    '<span class="large hh2">{</span>' .
    '<span class="array"><span class="tbl l1">' .
    '<span><span><i>x</i></span></span>' .
    '<span><span><i>y</i></span></span>' .
    '</span></span>';

is_ '\mathbb{R}\mathcal{C}',
    '<span class="mathbb"><i>R</i></span><span class="mathcal"><i>C</i></span>';

is_ '\hat{x}', '<i>x&#770;</i>';
is_ '\hat{x + y}', '<span class="accent"><span>^</span><i>x</i>&nbsp;+&nbsp;<i>y</i></span>';
is_ '\tilde{x}', '<i>x&#771;</i>';

is_ '\Big|', '<span class="large hh2">|</span>';


is_u 'a + b', 1;
is_u '\frac{a}{b}', 2;
is_u '\hat{\frac{a}{b}}', 2;
is_u '\frac{a}{\frac{b}{c}}', 3;
is_u '\frac{\sum\limits_1^2}{\frac{b}{c}}', 4;
is_u '\begin{array}{l}1\\\\2\\\\3\end{array}', 3;
is_u '\begin{array}{l}\frac{1}{\frac{b}{c}}\\\\x & \prod\limits_1^2\end{array}', 5;

is_t "<\<text>> < 5", "<p>\xABtext\xBB \\lt 5\n</p>";
is_t '\\textbf{\\texttt{a}b}', '<b><code>a</code>b</b>';
is_t "\\begin{itemize}\n\\item aa\n\\item bb\n\\end{itemize}", "<ul>\n<li>aa</li>\n<li>bb</li>\n</ul>";
