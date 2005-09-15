package CATS::Diff;

use CATS::Misc qw(:all);
use File::Temp;
use Text::Balanced qw(extract_tagged extract_bracketed);

BEGIN
{
  use Exporter;

  @ISA = qw ( Exporter );
  @EXPORT = qw (check_diff 
		diff_table
		diff
		prepare_src
		prepare_src_show
		pas_normalize
		clean_src
		delete_obsolete_begins
		replace_proc
		replace_func
		create_new_code
		compare_subs
		cmp_advanced
		);
  @EXPORT_OK = qw($dbh);
}

our @keywords_pas = (
    "begin",
    "end",
    "if",
    "then",
    "else",
    "for",
    "downto",
    "to", 
    "do",    
    "while", 
    "repeat",
    "until", 
    "write", 
    "writeln",
    "read",   
    "readln",
    "random",
    "procedure",
    "function",
    "and",
    "or",
    "xor",
    "var",
    "const",
    "program",
    "goto",
    "label",
    "uses"
                     );

our @subs;
our $id;
our @rec_proc;
our @rec_func;
our $max;

#сравнивает простым diff'ом
sub cmp_diff
{
  my $tmp1 = shift;
  my $tmp2 = shift;

  $tmp1 eq $tmp2 and return 100;
  `diff -u $tmp1 $tmp2 >0000.txt`;
  open (DIFF_FILE, '<', '0000.txt');
  my $line = <DIFF_FILE>;	# в 1-й строке - инфо о 1-м файле
  !$line and return 100;
  $line = <DIFF_FILE>;	# во 2-й строке - инфо о 2-м файле
  $line = <DIFF_FILE>;	# в 3-й строке - заголовок ханка
  $line = <DIFF_FILE>;	# c 4-й строки всё начинается
  my $plus=-1;
  my $minus=-1;
  my $lines=1;
  while ($line)
  {
    $line =~ m/^@@.*?/ or $lines++;
    
    $line =~ m/^\+.*?/ and $plus++;
    $line =~ m/^\-.*?/ and $minus++;
    
    $line = <DIFF_FILE>;
  }
  int 100 * (1 - ($plus>$minus? $plus/$lines : $minus/$lines));
}

# сравнивает специальным алгоритмом
sub cmp_advanced
{
  my $tmp1 = shift;
  my $tmp2 = shift;
  
  $tmp1 eq $tmp2 and return 100;	# если один и тот же файл

  open (FILE, $tmp1);			# читаем из файла первый текст
  $/=undef;				# сразу полностью
  my $src1 = <FILE>;	
  $src1 = replace_proc($src1);		# макроподставляем процедуры
  $src1 = replace_func($src1);		# макроподставляем функции
  $src1 = create_new_code($src1);	# обрабатываем остальной код

  open (FILE, $tmp2);			# то же самое делаем со вторым
  $/=undef;
  my $src2 = <FILE>;
  $src2 = replace_proc($src2);
  $src2 = replace_func($src2);
  $src2 = create_new_code($src2);

  my $comp = compare_subs($src1,$src2);	# сравниваем
  int $comp*100/$max;		# выдаем процент совпадений
}

# очищает код от всего ненужного, запихивает в tmp-файл и возвращает имя этого tmp-файла
sub prepare_src
{
  my $src = shift;
  $src = clean_src($src);
  $src = pas_normalize($src);
  my ($fh, $fname) = tmpnam;
  syswrite $fh, $src, length($src);
  $fname;
}

# убираем из кода все лишнее
sub clean_src
{
  my $src = shift;
  $src =~ s/^program.*?;//i;	# убираем PROGRAM, если есть
  $src =~ s/\/\/.*//gs;		# однострочные дельфийские комментарии
  $src =~ s/\{[^\}]*?\}//gs;		# и многострочные паскалевские комментарии

  $src =~ s/assign.*?\(.*?;//gi;	# assign тоже стоит убрать, т.к. они везде будут
  $src =~ s/assignfile.*?\(.*?;//gi;	# assignfile - то же самое, только в дельфи
  $src =~ s/close.*?\(.*?;//gi;		# и close тоже
  $src =~ s/reset[\s,\(].*?;//gi;	# reset/rewrite
  $src =~ s/rewrite[\s,\(].*?;//gi;
  
  # уничтожение ввода-вывода, вместе с циклами или условными операторами (если надо)
  $src =~ s/\s/ /g;
  $src =~ s/begin/begin;/gi;
  $src =~ s/else/;else/gi;
  foreach ('read','write')			# кстати, этим циклом убиваются и read/write, и readln/writeln
  {
    while ($src =~ s/;[^;]*?$_.*?;/;/gi){}	# это надо делать именно так, без while не работает
  }
  
  $src =~ s/;else/else/gi;
  $src =~ s/begin;/begin/gi;
  $src =~ s/;;/;/g;				# на всякий случай
  
  $src;
}

#ставит скобочки везде, где происходит вызов функции или процедуры
sub call_brackets
{
  my $src = shift;
  
  my @names;
  push @names, $src =~ m/PROCEDURE(\w+)[^\w\(]/g;	# имена всех процедур без параметров
  push @names, $src =~ m/FUNCTION(\w+)[^\w\(]/g;	# имена всех функций без параметров
  
  foreach (@names)
  {
    $src =~ s/([A-Z\W]$_)([A-Z\W])/$1\(\)$2/g ;
  }
  
  $src =~ s/(([A-Z\W])\w*)\(\):=/$1:=/g;	# тут мы убираем лишние скобочки из определения функции
  
  $src;
}

# специальное форматирование текста
sub pas_normalize
{
  my $src = shift;
  #$src = clean_src($src);
  
  $src = ';'.$src;
  $src =~ tr/A-Z/a-z/;		# преобразуем весь код в нижний регистр
# заменяем все ключевые слова на верхний регистр
  $src =~ s/(\W$_\W)/\U$1\L/g foreach (@keywords_pas);
  $src =~ s/program .*?;//;
  
# заменяем div и mod на значки
  $src =~ s/(\W)div(\W)/$1\\$2/g;	# div на \
  $src =~ s/(\W)mod(\W)/$1%$2/g;	# mod на %
  
# убираем inc и dec
  $src =~ s/(\W)inc\((\w*?)\)/$1$2:=$2+1/g;
  $src =~ s/(\W)dec\((\w*?)\)/$1$2:=$2-1/g;
  
  #$src =~ s/[a-z]+\w*?\s*?\(/f\(/g;			# все вызовы функций заменили на f
  #$src =~ s/[a-z]+\w*?\s*?([^a-zA-Z_0-9(])/\$$1/g;	# все имена переменных заменили на $
  #$src =~ s/[+-]?[0-9]+/n/g;				# все целые числа заменили на n
  #$src =~ s/[+-]?\d+\.\d?([eE][+-]?\d)?/r/g;		# все вещественные числа заменили на r
  #$src =~ s/i\[/\@[/g;					# все имена матриц заменили на @
  
  $src =~ s/\s//gs;		#удалили пробелы

# поставили скобочки везде в вызовах процедур
  $src = call_brackets($src);
  
  $src =~ s/(PROCEDURE\w*?\(.*?)VAR(.*?\))/$1$2/g;	# удаление VAR из списка параметров процедур и функций
  $src =~ s/(FUNCTION\w*?\(.*?)VAR(.*?\))/$1$2/g;	# удаление VAR из списка параметров процедур и функций
  $src =~ s/$_.*?([A-Z])/$1/g foreach ('CONST','VAR','LABEL','USES'); # удалили блоки VAR, CONST, LABEL
  #$src =~ s/$_;//g foreach ('CONST','VAR','LABEL','USES');

  $src =~ s/END([^;])/END;$1/g;	# поставили ; после END там, где не было
  $src =~ s/([^;])END/$1;END/g;	# поставили ; перед END там, где не было и где на самом деле надо
  $src =~ s/([^;])UNTIL/$1;UNTIL/g;	# поставили ; перед END там, где не было и где на самом деле надо
  $src =~ s/;ELSE/ELSE/;	# удалили ; перед ELSE
  $src =~ s/BEGIN/BEGIN;/g;
  #$src =~ s/[^;]END;/\nEND;/g;
  #$src =~ s/([^A-Z]DO)([^\n])/$1\n$2/g;
  #$src =~ s/([^A-Z]THEN)([^\n])/$1\n$2/g;
  #$src =~ s/DOBEGIN/DO BEGIN/g;	# если BEGIN относится к некоторому DO, пусть они будуь на одной строчке
  #$src =~ s/THENBEGIN/THEN BEGIN/g;	# аналогично для THEN
  #$src =~ s/;(\w)/;\n$1/g;	#разнесли всё по строчкам (требуется только если сравниваем diff'ом)
  chop $src  ;
  
  #$src =~ s/\s/ /gs;

  $src;
}

# приведение текста программы к такому виду, чтобы можно было показывать юзеру
sub prepare_src_show
{
  my $src = shift;
  $src =~ tr/A-Z/a-z/;		# преобразуем весь код в нижний регистр

  $src = '<pre>'.$src.'</pre>';
  $src =~ s/(\W)($_)(\W)/$1<b>\U$2\L<\/b>$3/g foreach (@keywords_pas);	#ключевые слова делаем верхним регистром и жирным шрифтом
  
  $src;
}

# подстановка фактических параметров в процедуру вместо формальных
sub subst_params
{
  my $src = shift;	# текст процедуры
  my $formals = shift;	# список формальных параметров
  my $facts = shift;	# список фактичских параметров

  my @formal_list = split /,/,$formals;
  my @fact_list = split /,/,$facts;
  
  while(@fact_list)
  {
    $src =~ s/([^a-z])$formal_list[0]([^a-z])/$1$fact_list[0]$2/g;
    shift @formal_list;
    shift @fact_list;
  }  
  $src;
}

# макроподстановка процедур
sub replace_proc
{
  my $src = shift;
  my ($body, $pname, $formals, $n, @extr, $pos, $len, $facts, $body2subst);
  
  while ($src =~ s/PROCEDURE(\w*?)(\(.*?\))?;(.*?)BEGIN/$1 BEGIN/)
  {
    $pname = $1;		# имя процедуры
    $formals = $2;		# список формальных параметров
    $body = 'BEGIN'.$';		# тело процедуры
    
    $formals =~ s/;/,/g;		# список фактических параметров - список, разделенный запятыми
    $formals =~ s/:.*?(,|\))/$1/g;
    $formals =~ s/^\(//;		# убрали открывющую и закрывающую скобочки
    $formals =~ s/\)$//;
      
    @extr = extract_tagged($body, 'BEGIN','END', undef);	# выделили тело процедуры
    $body = $extr[0].';';
    $n = length($body)+length($pname)+1;
    
    substr ($src, index($src,$pname), $n, '');		# удалили определение процедуры
    
    if ($body =~ m/$pname\(/)	# встретили в теле процедуры вызов её же => это рекурсия
    {
      $body =~ s/([A-Z\W])$pname\(/$1call\(/g;	# обозначили рекурсивный вызов как call
      push @rec_proc, $body;		# поместили тело процедуры в массив рекурсивных процедур
      my $i = $#rec_proc;		# взяли индекс
      $src =~ s/$pname/prec$i/g;		# заменили имя в тексте программы
      
      return $src;		# больше ничего не стали делать с рекурсией
    }
    
    # теперь будем все вхождения процедуры макроподставлять
    while ($src =~ m/$pname(\(.*?\))?;/)
    {
      $pos = length ($`);	# нашли позицию, с которой встречается вызов процедуры
      $len = length ($&);	# длина, во всеми параметрами
      $facts = $1;		# список фактических параметров
      $facts =~ s/^\(//;
      $facts =~ s/\)$//;
      
      $body2subst = subst_params($body, $formals, $facts);
      substr ($src, $pos, $len, $body2subst);
    }
  }
  
  $src;
}

# макроподстановка функций
# замена
#	use (func(...))
# на
#	f = func(...)
#	use (f)
sub replace_func
{
  my $src = shift;
  my ($body, $fname, $formals, $ftype, $n, @extr, $pos, $len, $facts, $body2subst);
  
  while ($src =~ s/FUNCTION(\w*?)(\(.*?\))?:(\w*?);(.*?)BEGIN/$1 BEGIN/)
  {
    $fname = $1;		# имя функции
    $formals = $2;		# список формальных параметров
    $ftype = $3;		# тип возвращаемого значения
    $body = 'BEGIN'.$';		# тело функции
    
    $formals =~ s/;/,/g;		# получидся просто список, разделенный запятыми
    $formals =~ s/:.*?(,|\))/$1/g;
    $formals =~ s/^\(//;		# убрали открывющую и закрывающую скобочки
    $formals =~ s/\)$//;
    
    @extr = extract_tagged($body, 'BEGIN','END', undef);	# выделили тело процедуры
    $body = $extr[0].';';
    
    $n = length($body)+length($fname)+1;
    
    substr ($src, index($src,$fname), $n, '');		# удалили определение процедуры
    
    if ($body =~ m/$fname\(/)	# встретили в теле функции вызов её же => это рекурсия
    {
      $body =~ s/([A-Z\W])$fname\(/$1call(/g;	# обозначаем так рекурсивный вызов
      $body =~ s/([A-Z\W])$fname/$1result/;	# там, где не вызов => запись результата
      push @rec_func, $body;		# занесли в список рекурсивных функций
      $src =~ s/$fname/frec$#rec_func/g;	# заменили в тексте программы
      return $src;		# больше ничего не стали делать с рекурсией
    }
    $body =~ s/([A-Z\W])$fname(\W)/$1result$2/g;	# Пусть результат записывается в специальную переменную, как в Delphi   
    
    # теперь будем все вхождения функции макроподставлять
    while ($src =~ m/(;([^;]*?[^a-z;])?)$fname(\(.*?\))(.*?);/)
    {
      $pos = length ($`);	# нашли позицию, с которой встречается вызов процедуры
      my $plus = length ($1);
      $facts = $3;		# список фактических параметров
      $facts =~ s/^\(//;
      $facts =~ s/\)$//;
      
      $body2subst = subst_params($body, $formals, $facts);
      substr ($src, $pos+1, 0, $body2subst);		# подставили тело функции перед тем местом, где она была вызвана
      substr ($src, $pos+length($body2subst)+$plus, length($fname)+length($facts)+2, 'result');	# убрали вызов функции
    }
  }
  $src;
}

sub check_cond_brackets
{
  my $src = shift;
  my $kw1 = shift;
  my $kw2 = shift;
  
  my ($cond,$pos,$len);
  my @conds = $src =~ m/$kw1(.*?)$kw2/g;
  foreach (@conds)
  {
    $cond = $_;
    $pos = index($src, $_);	# позиция, с которой начинается условие
    $len = length ($cond);
    my @extr = extract_bracketed($cond,'()');
    if ($extr[0] ne $cond)
    {
      $cond = '('.$cond.')';
      substr ($src, $pos, $len, $cond);
    }
  }
  
  $src;
}

# удаление ненужных операторных скобочек
sub delete_obsolete_begins
{
  my $src = shift;

  $src =~ s/BEGIN(([^;])*?;)END;/$1/g;
  $src =~ s/^BEGIN/;BEGIN/;		# стоит привести к общему случаю, который обрабатывается ниже
  
  while ($src =~ m/;BEGIN/)		# если границы блока имеют смысл, перед BEGIN не может быть ; (т.к. либо DO BEGIN, либо  THEN BEGIN)
  {
    my $beg = 'BEGIN'.$';		# находим первую подстроку, начинающуюся с BEGIN
    
    my @extr = extract_tagged($beg, 'BEGIN', 'END', undef);	# вытащили весь этот блок целиком
    
    my $n = index($src, ';BEGIN');
    substr($src, $n, 7, ';');			# удалили BEGIN
    $n += length($extr[0])-8;
    substr($src, $n, 3, '');	# удалили END
    substr($src, $n, 1) eq ';' and substr($src, $n, 1, '');	# если после END стоит ; её тоже убираем
  }
  substr($src,0,1) eq ';' and substr($src,0,1,'');
  $src;  
}

# выделяет блоки BEGIN-END и заменяет их в тексте на sub
sub block2sub
{
  my $src = shift;
  $src = delete_obsolete_begins($src);
  $src =~ m/BEGIN/ or return $src;	# строк, начинающихся с BEGIN нет
  my $beg = 'BEGIN'.$';		# находим первую подстроку, начинающуюся с BEGIN
  
  my @extr = extract_tagged($beg, 'BEGIN', 'END', undef);	# из неё берём кусок со сбалансированными скобками BEGIN-END
  my $block = $extr[4];		# тут то, что между BEGIN и END
  my $fullblock = $extr[0];	# тут все вместе с BEGIN и END
  
  $block = block2sub($block) while ($block =~ m/BEGIN/);	# рекурсивно убираем все блоки BEGIN-END внутри нашего
  
  push @subs, $block;		# запоминаем блок в специальном массиве
  
  $id++;
  my $n=index($src, $fullblock);# заменяем всю последовательность на sub<номер>
  while ($n+1)	#замена регулярным выражением тут почему-то не работает, поэтому пришлось выходить из положения так
  {
    substr($src, $n, length($fullblock), 'sub'.$id);
    $n=index($src, $fullblock);
  }
  
  $src;
}

#переводит циклы REPEAT в WHILE по схеме:
# REPEAT <body> UNTIL <cond>; => <body>; WHILE <cond> DO <body>;
sub repeat2while
{
  my $src = shift;
  $src =~ m/REPEAT/ or return $src;
  while ($src =~ m/(.)?REPEAT/)
  {
    my $symb = $1;	#запомнили на всякий случай символ перед циклом (если там ;, то будем еще скобчки ставить)
    
    my $repeat = 'REPEAT'.$';
    
    my @extr = extract_tagged($repeat, 'REPEAT', '_REP', undef);
    my $body = $extr[4];		# тело цикла без операторных скобочек
    my $fullblock = $extr[0];		# цикл со скобочками
    
    $body =~ s/UNTIL([^;]*?);$//;
    my $cond = $1;			# условие цикла
    
    $body = delete_obsolete_begins($body);
# рекурсивно удаляем циклы REPEAT из тела нашего цикла (можно, конечно, здесь этого
# не делать, всё равно все удалится, но медленнее, т.к. тело подставляется два раза и
# убирать надо будет уже из двух мест)
    $body = repeat2while($body);
    $body = for2while($body);
    #$body = construct($body);
    if ($body =~ m/;.+?/g )
    {
      push @subs,$body;
      $id++;
      $body = 'sub'.$id;
    }
    my $n=index($src, $fullblock);	# нашли, где цикл сидит
    if ($symb eq ';' or !$symb)
    {
      substr($src, $n, length($fullblock), "$body;WHILENOT($cond)DO$body;")	# заменили
    }
    else
    {
      $id++;
      push @subs, "$body WHILENOT($cond)DO$body";
      substr($src, $n, length($fullblock), "sub$id");
    }
  }
  
  $src;
}

# переводит циклы FOR в циклы WHILE
sub for2while
{
  my $src = shift;
  
  my ($for,$param,$init,$finish,$sub_id);

# for-downto-do sub
  while ($src =~ m/(FOR(\w*?):=(\w*?)DOWNTO(\w*?)DOsub(\d*?);)/g)
  {
    ($for,$param,$init,$finish,$sub_id) = ($1,$2,$3,$4,$5);
    
    $subs[$sub_id-1] .= "$param:=$param-1;";
    $src =~ s/$for/BEGIN$param:=$init;WHILE($param>$finish)DOsub$sub_id;END;/g;
  }  
# for-to-do sub
  while ($src =~ m/(FOR(\w*?):=(\w*?)TO(\w*?)DOsub(\d*?);)/g)
  {
    ($for,$param,$init,$finish,$sub_id) = ($1,$2,$3,$4,$5);
    
    $subs[$sub_id-1] .= "$param:=$param+1;";
    $src =~ s/$for/BEGIN$param:=$init;WHILE($param<$finish)DOsub$sub_id;END;/g;
  }  
  
# for-downto-do simple statement
  $src =~ s/FOR(\w*?):=(\w*?)DOWNTO(\w*?)DO(.*?);/BEGIN$1:=$2;WHILE($1>$3)DOBEGIN$4;$1:=$1-1;END;END;/g;
# for-to-do simple statement
  $src =~ s/FOR(\w*?):=(\w*?)TO(\w*?)DO(.*?);/BEGIN$1:=$2;WHILE($1<$3)DOBEGIN$4;$1:=$1+1;END;END;/g;
  $src;
}

# последовательность преобразований, которую надо будет ко всему применять
sub change_code
{
  my $src = shift;
  
  $src = repeat2while($src);
  $src = for2while($src);
  $src = block2sub($src) while ($src =~m/BEGIN/);

  $src;
}

# тут будем мучить исходный код
sub create_new_code
{
  my $src = shift;

  $src =~ s/(UNTIL.*?;)/$1_REP/g;	#специально чтобы обозначать границы цикла REPEAT
  
  $src = block2sub($src) while ($src =~m/BEGIN/);
  $src = check_cond_brackets($src, 'WHILE', 'DO');
  $src = check_cond_brackets($src, 'IF', 'THEN');
  $src = change_code($src);

  my $i;
  while ($i<$id)
  {
    $subs[$i] = change_code($subs[$i]);
    $i++;
  }
  $src;
}

# сравнение выражений (пока в лоб, но потом может стоит доработать)
sub compare_expr
{
  my ($expr1,$expr2) = @_;
  ($expr1=~/^sub/ or $expr2=~/^sub/) and return 0;
  
  my ($copy1, $copy2) = ($expr1, $expr2);
  $copy1 =~ s/(\Wfrec)(\d*?)/$1/g;	# встречаются ли в выражениях вызовы рекурсивных функций
  $copy2 =~ s/(\Wfrec)(\d*?)/$1/g;
  
  # если не встречаются, просто сравниваем
  ($copy1 eq $expr1 or $copy2 eq $expr2) and return ($expr1 eq $expr2)*2;	
  
  # если встретились
  $copy1 ne $copy2 and return 0;	# если при этом структура выражений разная, то значит выражения тоже разные
  
  # если структура одинакова, просто сравниваем по очереди все функции
  my $m;
  while ($expr1=~/\Wfrec\d*?/ and $expr2=~/\Wfrec\d*?/)
  {
    $expr1=~s/(\Wfrec)(\d*?)/$1/;
    my $n1 = $2;
    $expr2=~s/(\Wfrec)(\d*?)/$1/;
    my $n2 = $2;
    
    $m += compare_subs('frec'.$n1, 'frec'.$n2)*2;
  }
  
}

# сравнение двух синтаксических конструкций
sub compare
{
  my ($str1,$str2) = @_;

  $str1=~/^WHILE/ and $str2=~/^WHILE/ and return compare_WHILE($str1,$str2);
  $str1=~/^IF/ and $str2=~/^IF/ and return compare_IF($str1,$str2);
  $str1=~/^GOTO/ and $str2=~/^GOTO/ and return 2;
  $str1=~/^prec/ and $str2=~/^prec/ and return compare_subs($str1,$str2);
  compare_expr($str1,$str2);
}

# сравнивает конструкции типа WHILE
sub compare_WHILE
{
  my ($str1,$str2) = @_;

  $str1 =~ /^WHILE\((.*?)\)DO(.*?)$/;
  my ($cond1,$body1) = ($1,$2);


  $str2 =~ /^WHILE\((.*?)\)DO(.*?)$/;
  my ($cond2,$body2) = ($1,$2);

  my $cmp_cond = compare_expr($cond1,$cond2);
  my $cmp_body;
  $cmp_body = compare_subs($body1,$body2);
  #$body1 =~ /^sub(\d*)$/ and 
  #$body2 =~ /^sub(\d*)$/ and $cmp_body = compare_subs($body1,$body2)
  #  or $cmp_body = compare_expr($body1,$body2);
  
  $cmp_cond==2 and $cmp_body==$max and return 2;	# если совпадают и условие, и тело цикла, значит они совпадают полностью
  !$cmp_cond and !$cmp_body and return 0;	# если ничего не совпадает, то значит они совсем разные
  1;  						# иначе существуют и сходства, и различия
}                                

#сравнивает конструкции типа IF-THEN-ELSE
sub compare_IF
{
  my ($str1,$str2) = @_;

  $str1 =~ /^IF\((.*?)\)THEN(.*?)(ELSE(.*?))?$/;
  my ($cond1,$then1,$else1) = ($1,$2,$4);

  $str2 =~ /^IF\((.*?)\)THEN(.*?)(ELSE(.*?))?$/;
  my ($cond2,$then2,$else2) = ($1,$2,$4);

  my ($cmp_then, $cmp_else);
  
  if (compare_expr($cond1,$cond2))
  { 
    #$then1 =~ /^sub(\d*)$/ and
    #$then2 =~ /^sub(\d*)$/ and
    $cmp_then = compare_subs($then1, $then2) or
    #$cmp_then = compare_expr($then1,$then2);
    
    $cmp_then==$max and $cmp_then = 2;
    
    if ($else1 or $else2)
    {
    #  $else1 =~ /^sub(\d*)$/ and 
    #  $else2 =~ /^sub(\d*)$/ and 
    #  $cmp_else = compare_subs($else1,$else2) or
      $cmp_else = compare_expr($else1,$else2);
    }
  }

  !$cmp_then and !$cmp_else and return 0;
  $cmp_then==2 and $cmp_else==$max and return 2;
  1;
}

# сравнение последовательности операторов
# вход: сама последовательность одной строкой (операторы разделены ;)
# выход: 
#	0 - совершенно все разное
#	1 - частично совпадают
#	2 - полностью совпадают
sub compare_subs
{
  my $sub1 = shift;
  my $sub2 = shift;

  $sub1 =~ /^sub(\d*)$/ and $sub1 = $subs[$1-1]; 
  $sub2 =~ /^sub(\d*)$/ and $sub2 = $subs[$1-1];
  
  $sub1 =~ /^prec(\d*)$/ and $sub1 = $prec[$1-1]; 
  $sub2 =~ /^prec(\d*)$/ and $sub2 = $prec[$1-1];

  $sub1 =~ /^frec(\d*)$/ and $sub1 = $frec[$1-1]; 
  $sub2 =~ /^frec(\d*)$/ and $sub2 = $frec[$1-1];
  
  $sub1 !~ /;/ and $sub2 !~ /;/ and return compare_expr($sub1, $sub2);

  my @stlist1 = split /;/, $sub1;
  my @stlist2 = split /;/, $sub2;

  my $s;
  my $comp;
  my $m;

  foreach $s (@stlist1)
  {
    $m += 2;
    foreach (0..$#stlist2)
    {
      if (my $c = compare($s,$stlist2[$_]))
      {
        splice (@stlist2,$_,1);
	$comp += $c;
	last;
      }
    }
  }
  $max = $m;
  $comp;
}

1;