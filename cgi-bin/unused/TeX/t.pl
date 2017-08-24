
use lib '../..';
use CATS::TeX::HTMLGen;

CATS::TeX::HTMLGen::initialize_styles();
print CATS::TeX::HTMLGen::gen_html_part('$p_i$');

1;
