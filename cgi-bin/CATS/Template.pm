package CATS::Template;

use strict;
use warnings;
use Template;
my $tt;

sub new
{
    my ($class, $file_name, $templates_path) = @_;
    
    $tt ||= Template->new({
        INCLUDE_PATH => $templates_path,
        COMPILE_EXT => '.ttc',
        COMPILE_DIR => "$templates_path/cache/"
    }) || die "$Template::ERROR\n";

    my $self = { vars => {}, file_name => $file_name };
    bless ($self, $class);

    return $self;
}

sub param
{
    my $self = shift;
    if (@_ == 1) {
        my $arg = shift;
        if (ref($_[0]) eq 'HASH') {
            @{$self->{vars}}{keys %$arg} = @{$arg}{keys %$arg};
        }
        else {
            return $self->{vars}->{$arg};
        }
    }
    else {
        my %args = @_;
        @{$self->{vars}}{keys %args} = @args{keys %args};
    }
}

sub output
{
    my $self = shift;
    my $res;

    $tt->process($self->{file_name}, $self->{vars}, \$res)
        or die $tt->error();
    $res;
}

1;
