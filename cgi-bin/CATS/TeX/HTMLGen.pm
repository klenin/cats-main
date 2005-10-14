# MathRender v1.2 by Matviyenko Victor  
package CATS::TeX::HTMLGen;
# часть первая, методы классов: вычисление высоты и генерация html

use strict;
#use warnings;

use HTML::AsSubs;
use CATS::TeX::TeXData;
use CATS::TeX::HTMLUtil;

use Exporter;
our @ISA = ("Exporter");
our @EXPORT = qw/&gen_html/;

# class: Node

# to local units:
sub Node::toloc
{
    # все значения рассчитываются относительно высоты normfont, 
    # но генерируются относительно высоты шрифта текущего элемента 
    # сам шрифт текущего элемента генерируется относительно шрифта объемлющего элемента 
    my ($self, $val) = @_;
    $val / $self->font; 
}
 
sub Node::font 
{
    # устанавливает и возвращает шрифт
    # В Letter он используется для генерации, в остальных узлах - для определения высоты
    # т.е играет роль масштаба
    my ($self, $val) = @_;
    $self->{font} ||= min(max ($val, minfont), maxfont) ; 
}
sub Node::bordstyle 
{
    # пришлось сделать inline стилем, потому что в в виде класса в IE6.0 не работает
    my ($self, $scale) = @_;
    $scale ||= 1;
    my %args = (Frac => "over", Sqrt => "arg", Over => "arg");
    my $arg = $self->{$args{ref $self}};
    "style" => mkstyle "border-width" => toem $arg->toloc( max $self->border*$scale, min_border());
}       
# признак наличия вложенных таблиц (если их нет, для некоторых узлов можно оптимизировать способ генерации html)
sub Node::isa_table() {1} 
sub Node::arg_font_class 
{
    # регистрируем класс шрифта для аргумента
    my ($self, $arg, $val) = @_;
    $arg ||= $self->{arg}; 
    my $rel = $self->toloc ( $val || $arg->font );
    $rel == 1 ? () : 
    need_class "relf". (undot $rel), "font-size" => toproc $rel;
}
sub Node::add_classes
{
    my ($self, $classes, $argref) = @_;
    $argref ||= $self->{arg};
    $classes ||= []; 
    use_class ($self->arg_font_class ($argref), @$classes);
}

#высота состоит из высоты над серединной линией (линией дроби) и высоты под серединной линией
sub Node::height {$_[0]->{height} ||= $_[0]->above() + $_[0]->below()} 
sub Node::border {$_[0]->{border} ||= 0.05*normfont} 
sub Node::genHTML {$_[0]->{arg}->genHTML} 

# html generators
sub Group::merge_letters
{
    # Все соседние буквы одного стиля собираем в одну (для оптимизации html-кода) 
    my ($self) = shift; 
    my $let; 
    my $args = $self->{args};
    for (@$args)
    {
        if (ref $_ eq "Letter" ) 
        {
            if ($let and $_->equal($$let) ) 
            {
                $_->{text} = $$let->text().$_->text();
                # помечаем как ненужные
                $$let= undef; 
            }
            $let = \$_;
        }
        else { $let = undef; }
    }
    # выкидываем помеченные;
    @$args = grep {defined $_} @$args; 
}
sub Group::pad_class 
{
    # класс выравнивания по высоте
    my ($self, $arg) = @_;
    my $padding = $self->below - $arg->below ; 
    $padding ?
    need_class "pad".(undot $padding), "padding-bottom" => toem $arg->toloc ($padding) : ()
}
sub Group::genHTML 
{
    my $self = shift; 
    my ($lheight) = ($self->{height}); 
    my @cells;
    $self->merge_letters;
    #my $istab = $self->isa_table;  
    return $self->{args}->[0]->genHTML if 1 == $self->args;
    my ($prev, $prevclass);
    for my $x ($self->args)
    {
        my $padclass = $self->pad_class($x); 
        if ($prev && ref $x eq "Letter" && $padclass eq $prevclass)
        {
            push @{$cells[-1]->[1]}, $x->genHTML ; 
        }
        else
        {
            push @cells, [{$self->add_classes([$padclass], $x)}, [$x->genHTML]];
        }
        if (ref $x eq "Letter" )
        {
            $prev = $x;
            $prevclass = $padclass; 
        } 
        else 
        {
            $prev = undef;
        }
    }    
    my $first = $cells[0];
    
    make_table [@cells] ;
} 
sub Frac::genHTML 
{
    my ($self) = @_; 
    my ($ov, $un) = ($self->{over}, $self->{under});
    make_table (
                [[{
                   $self->bordstyle, 
                   $self->add_classes([bordclass "bottom"], $ov)
                  },
                  $ov->genHTML]], 
                [[ {$self->add_classes([], $un)}, $un->genHTML]],
               );
}
sub Sqrt::genHTML 
{
    my $self = shift;
    need_class "sqr",
        'margin-top' => toem $self->toloc ($self->margin); 
    my $radlh = 1; 
    my $radfont = minfont / $radlh ;
    my $rdc = need_class
        "rad",
        'vertical-align' => 'top', 
        'text-align' => 'right', 
        'line-height' => toproc ($radlh), 
        'font-style' => '600',
        'font-family' => 'Arial';    
    my $spacefont = max 0, $self->height - $radfont - $self->margin ; 
    my $spc = need_class 
        "rspace".(undot $spacefont), 
        'font-size' => toproc (1),
        'line-height' => toem $self->toloc($spacefont);     
    need_class 
    'sqrdat', 
    'padding-left' => '1pt';
    make_table 
    {use_class "sqr"},
    [
     [{$self->bordstyle, use_class($spc, bordclass "right")}, '&nbsp;'],
     [{$self->bordstyle, rowspan => '2', $self->add_classes(["sqrdat", bordclass "top"])}, $self->{arg}->genHTML(),]
    ],
    [
     [{use_class $rdc, $self->arg_font_class(undef, $radfont)}, '&radic;']
    ]
}
sub Letter::genHTML 
{
    $_[0]->variable ? span({use_class "var"}, $_[0]->text) : $_[0]->text;
}
sub ParSym::genHTML 
{
    my $self = shift; 
    make_table 
    map {$self->{$_} ? ([[{$self->add_classes ([], $self->{$_}) }, $self->{$_}->genHTML]]): ()} qw/over arg under/;
}
sub Over::genHTML 
{
    my $self = shift;
    need_class "over", 'margin-top' => toem $self->toloc ($self->margin); 
    $self->isa_table ? 
    make_table 
    [[{$self->bordstyle, $self->add_classes(["over", bordclass "top"])}, $self->{arg}->genHTML]] : 
    span ({$self->bordstyle, $self->add_classes(["over", bordclass "top"])}, $self->{arg}->genHTML);
}
# class: Group
sub Group::isa_table 
{
    my $self = shift;
    return $self->{isatable} if exists $self->{isatable}; 
    $self->{isatable} ||= ref $_ ne "Letter" for $self->args;
    $self->{isatable};
}
sub Group::args {@{$_[0]->{args}}} 
sub Group::above {$_[0]->{above} ||= max 0, map $_->above, $_[0]->args;}
sub Group::below {$_[0]->{below} ||= max 0, map $_->below, $_[0]->args;}

# recursively_set_font
sub Group::rec_set_font
{
    my ($self, $val) = @_;
    $self->font ($val);
    my $args = $self->{args};
    $_->rec_set_font ($self->font) for grep ref ne "LeftRight", @$args; 
    my @idxs = grep ref $args->[$_] eq "LeftRight", 0..$#$args;
    for my $i (@idxs, reverse @idxs)
    {
        my $x = $args->[$i];
        if ($x ->{direction} eq '\left' and ref $args->[$i+1] and $args->[$i+1]->height) 
        {$x->rec_set_font ($args->[$i+1]->height)}
        elsif($args->[$i]->{direction} eq '\right' and $i>0 and $args->[$i-1]->height)
        {$x->rec_set_font ($args->[$i-1]->height)}
    } 
} 

# class: Letter

# для разных шрифтов коэффициенты различны и
# cвязаны с видом знаков + и - : 
# в основном 0.5 / 0.5
sub Letter::above {$_[0]->height * 0.580} 
sub Letter::below {$_[0]->height * 0.420} 
sub Letter::isa_table () {0}
sub Letter::height {$_[0]->{height} ||= line_height $_[0]->font}
sub Letter::rec_set_font {$_[0]->font ($_[1])}
sub Letter::equal 
{
    my ($self, $let) = @_;
    $self->font == $let->font and $self->variable == $let->variable; 
}

# class: Frac
sub Frac::rec_set_font 
{
    my ($self, $val) = @_;
    my $ko = 1; # коэф. произвольный 
    $self->{over}->rec_set_font($ko * $self->font($val)) ; 
    $self->{under}->rec_set_font($ko * $self->font) ; 
}
sub Frac::border {$_[0]->{border} ||= 0.05 } # коэф. произвольный 
sub Frac::above {$_[0]->{over}->height() + $_[0]->border / 2 }
sub Frac::below {$_[0]->{under}->height() + $_[0]->border / 2 }

# class: Sqrt корни
sub Sqrt::isa_table () {1}
sub Sqrt::above {$_[0]->{arg}->above + $_[0]->margin + $_[0]->border }
sub Sqrt::below {$_[0]->{arg}->below}
sub Sqrt::rec_set_font 
{
    my ($self, $val) = @_;
    $self->{arg}->rec_set_font($self->font($val) - $self->border - $self->margin) ; 
} 
sub Sqrt::border {$_[0]->{border} ||= 0.03} # коэф. произвольный
sub Sqrt::margin {$_[0]->{margin} ||= 0.15} # коэф. произвольный
# class: Sup, Sub степени и индексы

sub Sup::rec_set_font 
{
    my ($self, $val) = @_;
    $self->{arg}->rec_set_font(0.6 * $self->font($val));# коэф. произвольный
}
sub Sub::rec_set_font 
{
    my ($self, $val) = @_;
    $self->{arg}->rec_set_font(0.6 * $self->font($val)); # коэф. произвольный
}
sub Sup::above {$_[0]->{arg}->height} # коэф. произвольный (1)
sub Sup::below {0} # 1 - предыдущий
sub Sub::below {$_[0]->{arg}->height*0.8} # коэф. произвольный (1)
sub Sub::above {$_[0]->{arg}->height*0.2} # 1 - предыдущий
sub Sub::font {$_[0]->{arg}->font}
sub Sup::font {$_[0]->{arg}->font}

# class Matrix 
sub Matrix::isa_table {1}
sub Matrix::rec_set_font
{
    my ($self, $val) = @_;
    $self->font ($val);
    do {$_->rec_set_font($self->font*0.9) for @$_} for $self->rows;
}
sub Matrix::height
{
    my $self = shift; 
    return $self->{height} if $self->{height};
    for my $row ($self->rows)
    {
        $self->{height} += max map {$_->height} @$row;
    }
    $self->{height};
}
sub Matrix::above {$_[0]->height * 0.5} 
sub Matrix::below {$_[0]->height * 0.5}
sub Matrix::rows {@{$_[0]->{rows}}}
sub Matrix::genHTML
{
    my $self = shift;
    make_table (map {[map {[$_->genHTML]} @$_]} $self->rows());
}

# class: ParSym - интегралы, суммы, пределы
sub ParSym::isa_table {1}
sub ParSym::rec_set_font
{
    my ($self, $val) = @_; 
    # коэф. произвольный 
    $_ && $_ ->rec_set_font (0.6 * $self->font ($val)) for $self->{over}, $self->{under}; 
    $self->{arg}->rec_set_font ($self->font);
}
sub ParSym::ovh {$_[0]->{over} && $_[0]->{over}->height || 0} 
sub ParSym::unh {$_[0]->{under} && $_[0]->{under}->height || 0} 
sub ParSym::above {$_[0]->ovh + 0.5 * $_[0]->{arg}->height}
sub ParSym::below {$_[0]->unh + 0.5 * $_[0]->{arg}->height} 

# class: Over - вектора
sub Over::isa_table 
{
    my $self = shift; 
    $self->{arg}->isa_table;
}
sub Over::above {$_[0]->{arg} -> height()* 0.5 + $_[0]->border + $_[0]->margin}
sub Over::below {$_[0]->{arg} -> height() * 0.5}
sub Over::border {$_[0]->{border} ||= 0.06 * $_[0]->font} # коэф. произвольный 
sub Over::rec_set_font 
{
    my ($self, $val) = @_;
    $self->{arg}->rec_set_font($self->font($val)) ; 
} 
sub Over::margin {$_[0]->{margin} ||= 0.05 * minfont} # коэф. произвольный 
1;