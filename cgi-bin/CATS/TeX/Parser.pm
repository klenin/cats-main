# MathRender v1.2 by Matviyenko Victor  
# разбор нотации ТеХ
package CATS::TeX::Parser; 
use strict;
#use warnings;

use CATS::TeX::TeXData;
use Text::TeX;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(parse); 

{
    package Node; 
    sub new
    {
        my $class = shift;
        bless {@_}, $class;
    }
    sub is_boxed {$_[0]->{boxed}}
    package Group;
    package Frac;
    package Sub;
    package Sup; 
    package Letter;
    sub text 
    {
        return $_[0]->{text} if exists $_[0]->{text};
        my $arg = $_[0]->{arg};
        $_[0]->{text} =
          exists $CATS::TeX::TeXData::symbols{$arg} ? $CATS::TeX::TeXData::symbols{$arg} : $arg;
    }
    sub variable 
    {
        return $_[0]->{isavar} if exists $_[0]->{isavar};
        $_[0]->{isavar} = $_[0]->text =~ /^[a-zA-Z]+$/ ? 1:0;
    } 
    package Bracket;
    package ParSym;
    package LeftRight;
    package Matrix;
    package Over;
}
# просто немного более информативное название 
sub Text::TeX::Chunk::src {shift->[0]}

{
 @Group::ISA = 
 @Frac::ISA = 
 @Sup::ISA = 
 @Sub::ISA =
 @Over::ISA = 
 @Sqrt::ISA = 
 @Letter::ISA = qw/Node/; 
 @Bracket::ISA = qw/Letter/;
 @LeftRight::ISA = qw/Letter/;
 @ParSym::ISA = qw/Node/; #?
 @Matrix::ISA = qw/Node/; #?
}


my $scanner;
my $current_token;
my @tok_buffer; 
my $math_mode = undef;
sub split_text 
{
    # разбивает лексему на символы и возвращает текущую лексему 
    # (первый символ бывшей лексемы)
    unshift @tok_buffer, split(//, $current_token);
        next_token(); 
}
sub next_token () 
{
    # используется модуль Text::Tex для разбиения строки на лексемы
    return $current_token = shift @tok_buffer if (@tok_buffer); 
    my $curtok;
    do {$curtok = $scanner->eat or return $current_token = undef} while (not defined $curtok->src); 
    if ($math_mode)
    {
        # убираем пробелы в математической моде
        push @tok_buffer, split(' ', $curtok->src);
    } 
    else 
    {
        push @tok_buffer, $curtok->src;
    }
    next_token (); 
}
 
sub match 
{
    return if not defined $_[0];
    #fail
    die $_[0]."expected but $current_token found" unless $current_token eq $_[0]; 
    next_token();
} 

sub parse_the
{
    # parse known object
    my $class = shift; 
    next_token(); 
    die "fail to construct object" if not defined $class;
    my $obj= {}; 
    my $field;
    $obj->{$field} = new_obj() while $field = shift;
    bless $obj, $class;
}

sub new_obj 
{
    my $make_letter = sub
    {
        my $x = Letter->new (arg => $current_token);
        next_token();
        $x;
    }; 
    my @parlets = qw /lim max min sup inf/;
    my @parsym = (qw/ \int \sum \prod /, map "\\".$_, @parlets);
    my $make_parsym = sub
    {
        # разибраются все символы, которые могут иметь параметры сверху или снизу 
        my ($x, $arg)= ({}, $make_letter->() );
        my @x;
        die "bad argument ". $arg->{arg} unless grep ($_ eq $arg->{arg}, @parsym); 
        do {$arg->{arg} = $_ if "\\".$_ eq $arg->{arg}} for @parlets;
        if ($current_token eq '_')
        {
            next_token;
            $x->{under} = new_obj(); 
        }
        if ($current_token eq '^')
        {
            next_token;
            $x->{over} = new_obj();
            if ($current_token eq '_' and not exists $x->{under})
            {
                next_token;
                $x->{under} = new_obj(); 
            } 
        } 
        if ($x->{under} or $x->{over})
        {
            $x->{arg} = $arg;
            return bless $x, "ParSym";
        }
        else {$arg} 
    };
    my $make_lr = sub 
    {
        # команды \left, \right задают высоту скобки, равную высоте следующего/спредыдущего символа
        # поэтому они не обязаны быть парными, но для использования их с группой символов, ее нужно заключить
        # в фигурные скобки: \left( {a+\frac x y} \right) 
        die "wrong handler for $current_token" unless grep $current_token eq $_, qw/\left \right/;
        my $obj = LeftRight->new (direction => $current_token);
        next_token; 
        die "wrong token $current_token after \\left or \\right " 
        unless grep $_ eq $current_token, qw/[ ] | ( ) {} /; 
        $obj->{arg} = $current_token;
        next_token;
        $obj; 
    }; 
    my $make_mat = sub 
    {
        # элементом строки матрицы является 1 символ, если требуется группа, ее нужно заключить в фигурные скобки
        next_token;
        my $self = bless {rows => []}, "Matrix";
        my $blank = Letter->new(arg => ' '); 
        match '{'; 
        for (my $currow; $current_token and $current_token ne '}'; $currow++)
        {
            while ($current_token and $current_token ne'\cr' )
            {
                push @{$self->{rows}->[$currow]}, $current_token eq '&' ? $blank : new_obj();
                last if $current_token eq '\cr';
                match '&';
            }
            next_token;
        }
        match '}'; 
        $self;
        
    }; 
    my %math_mode_handler = (
        (map {$_, $make_letter} keys %CATS::TeX::TeXData::symbols), # символы
        (map {$_, $make_parsym} @parsym), # интегралы, суммы...
        '\left' => $make_lr, # cкобки
        '\right' => $make_lr, 
        '\matrix'=> $make_mat, 
        '\frac' => sub { parse_the qw(Frac over under) },
        '\sqrt' => sub { parse_the qw(Sqrt arg) },
        '^' => sub { parse_the qw(Sup arg) },
        '_' => sub { parse_the qw(Sub arg) },
        '\=' => sub { parse_the qw/Over arg/ }, #вектора
        '{' => sub { new_group ('{', '}') },
    ); 
    
    my %non_math_mode_handler = (
        '$' => sub { new_group ('$', '$') },
        '\\' => sub { Letter->new(type => "eol") }
    );
    
    my $handler = $math_mode ? \%math_mode_handler : \%non_math_mode_handler;
    $handler = $handler->{$current_token}; 
    return $handler-> () if $handler;     
    # eсли не удалось разобрать текущую  лексему, считаем ее текстом
    my $char = split_text;
    my $ret = Letter->new (arg => $char);
    next_token;
    $ret;
}
sub new_group
{
    my ($left, $right) = @_;
    $math_mode = 1 if $left eq '$';     
    match $left;
    my @group; 
    push @group, new_obj() while defined $current_token and ($current_token ne $right or not defined $right); 
    my $obj = bless ({args => \@group, type => $math_mode ? 'math' : 'text'}, "Group");
    $math_mode = undef if $right eq '$';
    match $right; 
    $obj;    
}
sub parse 
{
    my $string = shift; 
    $scanner = Text::TeX::OpenFile->new (undef, 'string' => $string, 'tokens'=> {} ) ; 
    next_token;
    return new_group; 
}
1;