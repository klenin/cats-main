use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 4;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::TeX::Lite;

sub tex { CATS::TeX::Lite::asHTML(CATS::TeX::Lite::parse($_[0])) }

sub is_ { is tex($_[0]), $_[1], "tex $_[0]" }

is_ '1', '<span class="num">1</span>';
is_ 'a', '<i>a</i>';
is_ 'a+b', '<i>a</i>+<i>b</i>';
is_ 'a \le b', '<i>a</i>&nbsp;&le;&nbsp;<i>b</i>';
