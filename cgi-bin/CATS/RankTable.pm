package CATS::RankTable;

use lib '..';
use strict;
use warnings;
use Encode;

use CATS::Constants;
use CATS::Misc qw($dbh);

use fields qw(contest_list hide_ooc hide_virtual);

sub new
{
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}


1;
