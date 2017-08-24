# MathRender v1.2 by Matviyenko Victor  
# генерация MathML
package CATS::TeX::MMLGen;
use warnings;
use strict;
use CATS::TeX::TeXData;
use CATS::TeX::Parser;
#use Data::Dumper;
use HTML::AsSubs;

# наделаем функций для генерации тегов: 
my @tags = qw/math mo mi mn mrow msub msup msqrt mfrac munderover mover munder mtable mtr mtd/;
my @code;
push @code, "sub $_ {HTML::AsSubs::_elem('$_', \@_);}\n" for @tags;
eval join('', @code);
die $@ if $@;
sub Letter::genMML
{
    my $self = shift;
    $self->variable ? 
    mi ($self -> text):
    mo ($self -> text);
}
sub Frac::genMML
{
    my $self = shift;
    mfrac ($self->{over}->genMML, $self->{under}->genMML); 
}
sub Sqrt::genMML
{
    my $self = shift;
    msqrt ($self->{arg}->genMML); 
}
sub Group::genMML 
{
    my $self = shift; 
    my $args = $self->{args};
    # для sup и sub нужен второй аргумент. выбираем просто соседний символ слева, если есть
    for my $i (my @needarg = grep ref $args->[$_] eq "Sup" || ref $args->[$_] eq "Sub", 0..$#$args)
    {
        die "not enough arguments for msup/msub" unless $i>0;
        $args->[$i]->{arg2} = $args->[$i-1];
        $args->[$i-1] = undef; 
    }
    # throw out garbage
    @$args = grep {defined $_} @$args; 
    mrow (map $_->genMML(), @{$self->{args}});
}
sub Sup::genMML
{
    my $self = shift;
    msup ($self->{arg2}->genMML, $self->{arg}->genMML); 
}
sub Sub::genMML
{
    my $self = shift;
    msub ($self->{arg2}->genMML, $self->{arg}->genMML); 
}
sub ParSym::genMML
{
    my $self = shift;
    my ($ov, $un) = ($self->{over}, $self->{under});
    $ov && $un && return munderover ($self->{arg}->genMML, $un->genMML, $ov->genMML);
    $ov && return mover ($self->{arg}->genMML, $ov->genMML);
    $un && return munder($self->{arg}->genMML, $un->genMML);
    $self->{arg}->genMML;
} 
sub LeftRight::genMML
{
    my $self = shift;
    mo ($self -> text);
}
sub Matrix::genMML
{
    my $self = shift;
    mtable (map {+mtr ( map +mtd($_->genMML), @$_)} @{$self->{rows}});
}
sub Over::genMML
{
    my $self = shift;
    mover ($self->{arg}->genMML, mo ('&OverBar;'));
}
sub gen_mml
{
    my $string = shift;
    my %par = @_;
    my $x = CATS::TeX::Parser::parse $string;
    my $src = math( {xmlns => 'http://www.w3.org/1998/Math/MathML'}, $x->genMML );
    my $txt = '<!DOCTYPE math PUBLIC "-//W3C//DTD MathML 2.0//EN" "http://www.w3.org/Math/DTD/mathml2/mathml2.dtd">'; 
    $txt .= "\n".$src->as_HTML('<>', $par{step}); 
}
1;