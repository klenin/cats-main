package CATS::Template;

use strict;
use warnings;
use Template;
use HTML::Template;
use Encode;
my $tt;

sub new
{
    my ($class, $file_name, $cats_dir) = @_;
    my $self;
    if ($file_name =~ /\.tt$/) {
        my $templates_path = $cats_dir . '../tt';
        $tt ||= Template->new({
            INCLUDE_PATH => $templates_path,
            COMPILE_EXT => '.ttc',
            COMPILE_DIR => "$templates_path/cache/"
        }) || die "$Template::ERROR\n";
        $self = {};
        $self->{vars} = {};
        $self->{file_name} = $file_name;
        bless ($self, $class);
    }
    else {
        my $utf8_encode = sub {
            my $text_ref = shift;
            #Encode::from_to($$text_ref, 'koi8-r', 'utf-8');
            $$text_ref = Encode::decode('koi8-r', $$text_ref);
        };
        $self = HTML::Template->new(
            filename => $cats_dir . "../templates/std/$file_name", cache => 1,
            die_on_bad_params => 0, filter => $utf8_encode, loop_context_vars => 1);
    }

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
