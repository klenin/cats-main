package CATS::Contest::Utils;

use strict;
use warnings;

use List::Util qw(reduce);

use CATS::DB;

sub common_seq_prefix {
    my ($pa, $pb) = @_;
    my $i = 0;
    ++$i while $i < @$pa && $i < @$pb && $pa->[$i] eq $pb->[$i];
    [ @$pa[0 .. $i - 1] ];
}

sub common_prefix { join ' ', @{(reduce { common_seq_prefix($a, $b) } map [ split /\s+|_+/ ], @_) || []} }

sub sanitize_clist { sort { $a <=> $b } grep /^\d+$/, @_ }

sub contest_group_by_clist {
    $dbh->selectrow_array(q~
        SELECT id FROM contest_groups WHERE clist = ?~, undef,
        $_[0]);
}

1;
