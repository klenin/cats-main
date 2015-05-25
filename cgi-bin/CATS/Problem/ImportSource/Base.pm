package CATS::Problem::ImportSource::Base;

use strict;
use warnings;

sub new
{
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
    $self;
}

sub get_sources { (undef, undef); }

sub get_guids { (); }


1;
