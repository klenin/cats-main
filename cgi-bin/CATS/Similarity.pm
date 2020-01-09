package CATS::Similarity;

use strict;
use warnings;

use Encode;
use Digest::MD5;

sub preprocess_source {
    my ($req, $s) = @_;
    my $h = $req->{hash} = {};
    my $line = 0;
    my $max_lines = $s->{max_lines} || 1000;
    for (split /\n/, $req->{src}) {
        ++$line < $max_lines or last;
        $_ = Encode::encode('WINDOWS-1251', $_);
        use bytes; # MD5 works with bytes, prevent upgrade to utf8
        s/\s+//g;
        if ($s->{collapse_idents}) {
            s/[a-zA-Z_][a-zA-Z_0-9]*/A/g;
        }
        else {
            $_ = uc($_);
        }
        s/\d+/1/g if $s->{collapse_nums};
        $h->{Digest::MD5::md5_hex($_)} = 1;
    }
    undef;
}

sub similarity_score {
    my ($i, $j) = @_;
    my $sim = 0;
    $sim++ for grep exists $j->{$_}, keys %$i;
    2 * $sim / (keys(%$i) + keys(%$j));
}

sub similarity_score_2 {
    my ($req1, $req2, $s) = @_;
    preprocess_source($_, $s) for ($req1, $req2);
    similarity_score(map $_->{hash}, $req1, $req2);
}

1;
