package CATS::Similarity;

use strict;
use warnings;

use Encode;
use Digest::MD5;

sub preprocess_source {
    my ($req, $s) = @_;
    my $h = $req->{hash} = {};
    for (split /\n/, $req->{src}) {
        $_ = Encode::encode('WINDOWS-1251', $_);
        use bytes; # MD5 works with bytes, prevent upgrade to utf8
        s/\s+//g;
        if ($s->{collapse_idents}) {
            s/(\w+)/A/g;
        }
        else {
            s/(\w+)/uc($1)/eg;
        }
        s/\d+/1/g;
        $h->{Digest::MD5::md5_hex($_)} = 1;
    }
    return;
}

sub similarity_score {
    my ($i, $j) = @_;
    my $sim = 0;
    $sim++ for grep exists $j->{$_}, keys %$i;
    $sim++ for grep exists $i->{$_}, keys %$j;
    return $sim / (keys(%$i) + keys(%$j));
}

1;
