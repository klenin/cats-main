package CATS::Topics;

use strict;
use warnings;

sub new {
    my ($class, $topics) = @_;
    my $self = bless { levels => {} }, $class;
    if ($topics) {
        $self->add($_) for @$topics;
    }
    $self;
}

my $empty = { code_prefix => '', name => '' };

sub add {
    my ($self, $topic) = @_;
    my $code = $topic->{code_prefix};
    defined $code or die;
    my $level = $self->{levels}->{length $code} //= {};
    die "Duplicate topic: $code" if exists $level->{$code};
    $level->{$code} = $topic;
}

sub get {
    my ($self, $code) = @_;
    $code or return;
    for (my $i = length $code; $i > 0; --$i) {
        my $level = $self->{levels}->{$i} or next;
        my $prefix = substr($code, 0, $i);
        return $level->{$prefix} if exists $level->{$prefix};
    }
    undef;
}

1;
