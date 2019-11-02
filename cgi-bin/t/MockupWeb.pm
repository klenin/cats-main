package MockupWeb;

sub new {
    my ($class, %rest) = @_;
    bless { p => \%rest }, $class
}

sub web_param { $_[0]->{p}->{$_[1]} }

1;
