package CATS::Web::Mockup;

sub new {
    my ($class, %rest) = @_;
    bless { p => \%rest }, $class
}

sub web_param {
    my ($self, $name) = @_;
    my $v = $self->{p}->{$name};
    !wantarray ? $v : $v ? @$v : ();
}

1;
