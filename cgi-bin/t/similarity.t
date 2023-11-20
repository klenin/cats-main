use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 10;

use lib File::Spec->catdir($FindBin::Bin);
use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Similarity;

sub sc { CATS::Similarity::similarity_score(map $_->{hash}, @_) }

{
    my $req1 = { src => "aa\nbb" };
    my $req2 = { src => "bb\ncc" };
    CATS::Similarity::preprocess_source($_, {}) for ($req1, $req2);
    is sc($req1, $req2), 0.5, 'basic';
}

{
    my $req1 = { src => "aa\nbb" };
    my $req2 = { src => "bb\ncc" };
    CATS::Similarity::preprocess_source($_, { collapse_idents => 1 }) for ($req1, $req2);
    is sc($req1, $req2), 1.0, 'collapse idents';
}

{
    my $req1 = { src => "print(a)\n    a = 0" };
    my $req2 = { src => "print( b )\nb = 0" };
    my ($r, $c) = CATS::Similarity::recommend_replacements($req1, $req2, {}, {});
    is_deeply $r, [ 'a b' ], 'recommend simple str';
    is_deeply $c, [ 2 ], 'recommend simple cnt';
}

{
    my $req1 = { src => "a a\nc\na a\n!c\n" };
    my $req2 = { src => "b a\nd\nb a\n!d\n" };
    my ($r, $c) = CATS::Similarity::recommend_replacements($req1, $req2, {}, {});
    is_deeply $r, [ 'c d' ], 'recommend consistent line str';
    is_deeply $c, [ 2 ], 'recommend consistent line cnt';
}

{
    my $req1 = { src => "a\nc\na+\nc c\n" };
    my $req2 = { src => "b\nd\nb+\nd d\n" };
    my ($r, $c) = CATS::Similarity::recommend_replacements($req1, $req2, {}, {});
    is_deeply $r, [ 'c d', 'a b' ], 'recommend order str';
    is_deeply $c, [ 3, 2 ], 'recommend order cnt';
}

{
    my $req1 = { src => "a\nc\na+\nc c\n" };
    my $req2 = { src => "b\nd\nb+\nd d\n" };
    my ($r, $c) = CATS::Similarity::recommend_replacements($req1, $req2, {}, { c => 1 });
    is_deeply $r, [ 'a b' ], 'recommend except str';
    is_deeply $c, [ 2 ], 'recommend except cnt';
}

{
    my $req1 = { src => "a = int(input())\nfor i in range(a):\n" };
    my $req2 = { src => "kolich = int(input())\nfor i in range(kolich):\n" };
    my ($r, $c) = CATS::Similarity::recommend_replacements($req1, $req2, {}, { c => 1 });
    is_deeply $r, [ 'a kolich' ], 'recommend except str';
    is_deeply $c, [ 2 ], 'recommend except cnt';
}
1;
