package CATS::Problem::Source::Base;

use strict;
use warnings;

sub new
{
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
    $self;
}

sub init { 0 }

sub get_zip { 0 }

sub find_members { () }

sub read_member { 0 }

sub finalize { 0 }

sub error
{
    my ($self, $msg) = @_;
    $self->{logger}->error($msg) if exists $self->{logger} && defined $self->{logger};
}

sub note
{
    my ($self, $msg) = @_;
    $self->{logger}->note($msg) if exists $self->{logger} && defined $self->{logger};
}

sub warning
{
    my ($self, $msg) = @_;
    $self->{logger}->warning($msg) if exists $self->{logger} && defined $self->{logger};
}


1;
