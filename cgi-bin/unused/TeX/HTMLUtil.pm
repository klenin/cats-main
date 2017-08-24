# MathRender v1.2 by Matviyenko Victor  
package CATS::TeX::HTMLGen;
# часть вторая, вспомогательная: 
# разнообразные вспомогательные функции для генерации стилей и тегов

use strict;
#use warnings;
use HTML::AsSubs;
#use Data::Dumper;

use CATS::TeX::Parser;

# этой функции не хватает в AsSubs 
sub span{HTML::AsSubs::_elem('span', @_)}
# а функцией &tr(...) из AsSubs неудобно пользоваться
sub TR{HTML::AsSubs::_elem('tr', @_)}


#хеш, в котором классы стилей хранятся
my %styles_; 

# metrics 

#my $normal_font_size; #значение произвольное
# шрифт задается в пунктах и перевоодится в миллиметры для повышения точности
sub normfont() {1} 
sub minfont() {normfont * 0.7} #значение произвольное
sub maxfont() {normfont * 4} #значение произвольное
# должно работать для шрифтов >= 12pt, пришлось ввести, потому что Opera не отображает тонкие линии
sub min_border () {normfont/20} 
#при меньшем значении высокие символы вроде значка интеграла будут обрезаться
sub line_height($) {$_[0] * 1.5} 

# преобразование значений
sub trim($) {sprintf "%.2f", $_[0]}
sub toem($) {trim ($_[0]).'em'}
# значение в процентах:
sub toproc($) {(100 * trim $_[0]) . "\%"}
# делаем строку из действительного числа(для генерации имен стилей) 
sub undot($) {100 * trim $_[0]} 

sub max(@) 
{
    my $max = shift;
    $_ > $max and $max = $_ for @_;
    $max;
}
sub min(@) 
{
    my $min = shift;
    $_ < $min and $min = $_ for @_;
    $min;
} 

# таблицы и стили: 
sub mkstyle
{
    #из хеша атрибутов стиля составляет новый стиль в виде строки
    my(%attr) = @_;
    my($ret, $k, $v) ;
    $ret.= "$k: $v\; " while ($k, $v) = each %attr;
    $ret;
}
# добавляем к именам всех стилей префикс
sub spoil ($) {"mat_$_[0]";} 
sub use_class
{
    # вызывается всякий раз, когда нужно воспользоваться классом стиля
    # возвращает хеш, который передается генерирующим функциям типа make_table
    return () unless @_ = grep {$_} @_; 
    my @names = map spoil $_, @_; 
    return unless @names;
    exists $styles_{$_} or die "wrong class $_", caller for @names;
    (class => join " ", @names) ;
}
sub need_class 
{
    # сохраняет класс стиля в хеше, для последующего использования и генерации
    my($name, %attrib) = @_;
    $styles_{spoil $name} ||= {%attrib};
    $name; 
}
sub bordclass
{
    #создает класс границы с нужной стороны
    my $side = shift;
    die "bad side $side " unless grep $side eq $_, qw/top left right bottom/;
    need_class "brd_$side", "border-$side" => "solid black",
}

sub make_table 
# генерирует таблицу 
# in: attr ссылка на хеш атрибутов 
# data массив ссылок на масивы
{
    sub extract_params
    # разбирает параметры(данные и атрибуты) таблицы, строки или ячейки
    # из масива src и помещает в соответствующие хеши 
    {
        # первые 2 параметра могут быть непустыми хешами
        #(содержать значения атрибутов и данных по умолчанию) 
        my($attr, $data, $src) = @_;
        # если ссылка на хеш, извлекаем атрибуты 
        if(ref $src->[0] eq "HASH") 
        {
            my $ta = shift @$src;
            @$attr{keys %$ta} = values %$ta;
        } 
        # извлекаем данные(массив ссылок на массивы или просто одна строка) 
        push @$data, shift @$src while ref $src->[0] eq "ARRAY"; 
        push(@$data, +[shift @$src]) unless @$data;
    }
    #default table data: 
    my($attr, @rows) = {cellpadding => '0', cellspacing => '0'}; #, align => 'center'};
    extract_params $attr, \@rows, \@_;
    for my $row(@rows) 
    {
        #default row data:
        my($attr, @cells) = {}; 
        extract_params $attr, \@cells, $row; 
        for my $cell(@cells) 
        {
            #default cell data 
            my($attr, @data) = {}; 
            extract_params $attr, \@data, $cell; 
            # генерируем td 
            $cell = td $attr, map @$_, @data;
        }
        # генерируем tr 
        $row = TR $attr, @cells; 
    } 
    # собственно, библиотечная функция, которая генерирует таблицу
    table $attr, @rows;
}
sub initialize_styles 
{
    # в этот хеш по мере надобности добавляются стили, 
    %styles_= ();
    #включаем некоторые стили по умолчанию
    need_class "var", "font-family"=> "Times New Roman, Times, serif ", "font-style" => "italic";
}
# генерация
sub gen_styles 
{
    # генерирует стили (предполагается, что хеш стилей заполнен c помощью gen_body ) 
    # из стандартных windows-шрифтов только эти 2 содержат полный набор математических символов
    my %family =('font-family' => join ",", 'Lucida Sans Unicode', 'Arial Unicode Ms') ; 
    
    my $core = mkstyle 
    (
      'font-size' => '100%',
      'line-height' => toproc line_height(1), 
    );
    
    my $tab_style = mkstyle 
    (
      'padding' => '0 0 0 1 ',
      'margin-top' => '0',
      'margin-bottom' => '0',
      'border' => '0 0 0 0',
    ) ; 
    my $box_style = mkstyle
    (
      '-moz-box-sizing' => 'border-box',
      'box-sizing' => 'border-box'
    );
    my $span_style = mkstyle 
    (
      %family,
      'font-style' => 'normal',
      'text-align' => 'center',
      'vertical-align' => 'bottom',
    ) ; 
    my $all_classes;
    $all_classes .= "\n .TeX .$_ {" . mkstyle(%{$styles_{$_}}) . "}" for(sort keys %styles_) ; 
    join " ",
    "\n .TeX table{ display: inline; $core $box_style $tab_style }", 
    "\n .TeX td { $core $box_style $span_style}",
    "\n .TeX span { $core $span_style}",
    "\n .TeX tr { $core }",
    "$all_classes\n";
}
sub gen_body 
{
    # генерирует html без стилей
    # возвращает дерево html с помощью HTML::AsSubs
    my $string = shift;
    # получили синтаксическое дерево
    my $x = CATS::TeX::Parser::parse $string; 
    # установили шрифт(масштаб) 
    $x->rec_set_font(normfont) ; 
    initialize_styles;
    $x->genHTML;
}
sub gen_styles_html 
{
  style(gen_styles())->as_HTML('<>', "\t");
}
sub gen_html_part
{
  my $x = CATS::TeX::Parser::parse $_[0]; 
  $x->rec_set_font(normfont) ; 
  span({class => 'TeX'}, $x->genHTML)->as_HTML('<>', "\t");
}
sub gen_html 
{
    # создает страничку целиком 
    # парамeтры:
    # строка ТеХ
    # font - размер шрифта (просто строка, например "12pt", "140%" или "medium")
    # step - заполнение отступа в HTML коде (пробельные символы)
    my $string = shift;
    my %par = @_;
    $par{step} ||= "\t";
    my $font_val = $par{font} || "larger";
    my $body = body {style => "font-size: $font_val" }, gen_body($string);
    my $src = html(head (style gen_styles()), $body) ;
    $src->as_HTML('<>', $par{step}) ; 
}
1;