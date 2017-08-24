package CATS::Contest::Utils;

use strict;
use warnings;

use List::Util qw(reduce);

sub common_seq_prefix {
    my ($pa, $pb) = @_;
    my $i = 0;
    ++$i while $i < @$pa && $i < @$pb && $pa->[$i] eq $pb->[$i];
    [ @$pa[0 .. $i - 1] ];
}

sub common_prefix { join ' ', @{(reduce { common_seq_prefix($a, $b) } map [ split /\s+|_+/ ], @_) || []} }

1;
