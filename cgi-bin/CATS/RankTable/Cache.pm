package CATS::RankTable::Cache;

use strict;
use warnings;

use CATS::Config qw(cats_dir);

sub file_name {
    cats_dir() . './rank_cache/' . join ('#', @_, '');
}

sub files {
    my ($contest_id) = @_ or die;
    my @result;
    for my $virt (0, 1) {
        for my $ooc (0, 1) {
            my $f = file_name($contest_id, $ooc, $virt);
            push @result, $f if -f $f;
        }
    }
    @result;
}

sub remove {
    my ($contest_id) = @_ or die;
    unlink for files($contest_id);
}

1;
