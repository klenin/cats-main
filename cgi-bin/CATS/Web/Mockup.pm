package CATS::Web::Mockup;

sub new {
    my ($class, %rest) = @_;
    bless { p => \%rest }, $class
}

sub web_param {
    my ($self, $name) = @_;
    return wantarray ? () : undef if !exists $self->{p}->{$name};
    my $v = $self->{p}->{$name};
    wantarray && ref $v eq 'ARRAY' ? @$v : $v;
}

sub web_param_names { sort keys %{$_[0]->{p}} }

sub has_upload { 0 }

1;
