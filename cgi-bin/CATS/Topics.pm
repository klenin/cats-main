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
    push @{$level->{$code} //= []}, $topic;
}

sub get {
    my ($self, $code) = @_;
    $code or return [];
    my $topics = [];
    for (my $i = length $code; $i > 0; --$i) {
        my $level = $self->{levels}->{$i} or next;
        my $prefix = substr($code, 0, $i);
        push @$topics, @{$level->{$prefix}} if exists $level->{$prefix};
    }
    $topics;
}

sub diff {
    my ($old, $new) = @_;
    my $i = 1;
    ++$i while $i <= @$new && $i <= @$old && @$old[-$i]->{code_prefix} eq @$new[-$i]->{code_prefix};
    [ @{$new}[0 .. @$new - $i] ];
}

1;
