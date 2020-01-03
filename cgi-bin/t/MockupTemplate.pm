package MockupTemplate;

sub new {
    my ($class, %rest) = @_;
    bless { p => \%rest }, $class
}

sub param {
    my ($self, %rest) = @_;
    for my $k (keys %rest) {
        $self->{p}->{$k} = $rest{$k};
    }
}

sub get_params { $_[0]->{p} }

1;
