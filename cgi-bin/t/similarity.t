use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 2;

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

1;
