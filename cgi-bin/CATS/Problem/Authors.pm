package CATS::Problem::Authors;

use strict;
use warnings;

BEGIN {
   use Exporter;
   our @ISA = qw(Exporter);

   our @EXPORT = qw(get_git_author_info KLENINS_EMAIL DEFAULT_EMAIL DEFAULT_AUTHOR EXTERNAL_AUTHOR);
   # our %EXPORT_TAGS = (all => [ @EXPORT ]);
}

use constant {
   KLENINS_EMAIL   => 'klenin@gmail.com',
   DEFAULT_EMAIL   => 'unknown@example.com',
   DEFAULT_AUTHOR  => 'Unknown Author',
   EXTERNAL_AUTHOR => 'external'
};

sub make_author_info {
   my $h = {@_};
   my $res = {email => (defined $h->{email} ? $h->{email} : DEFAULT_EMAIL)};
   $res->{git_author} = $h->{git_author} if defined $h->{git_author};
   return $res;
}

my %authors_map = (
   'A. Klenin'           => make_author_info(email => KLENINS_EMAIL),
   'А. Zhuplev'          => make_author_info(git_author => 'A. Zhuplev'),
   'A. Zhuplev'          => make_author_info,
   'A. Maksimov'         => make_author_info,
   'Andrew Stankevich'   => make_author_info(git_author => 'A. Stankevich'),
   'B. Vasilyev'         => make_author_info,
   'D. Vikharev'         => make_author_info,
   'E. Vasilyeva'        => make_author_info,
   'Elena Kryuchkova'    => make_author_info(git_author => 'E. Kryuchkova'),
   'Georgiy Korneev'     => make_author_info(git_author => 'G. Korneev'),
   'I. Ludov'            => make_author_info,
   'I. Tuphanov'         => make_author_info,
   'I. Tufanov'          => make_author_info(git_author => 'I. Tuphanov'),
   'I. Burago'           => make_author_info,
   'Ludov I. Y.'         => make_author_info(git_author => 'I. Ludov'),
   'Michail Mirzayanov'  => make_author_info(git_author => 'M. Mirzayanov'),
   'Nick Durov'          => make_author_info(git_author => 'N. Durov'),
   'T.Chistyakov'        => make_author_info,
   'T. Chistyakov'       => make_author_info,
   'Roman Elizarov'      => make_author_info(git_author => 'R. Elizarov'),
   'А. Жуплев'           => make_author_info,
   'А. Зенкина'          => make_author_info,
   'А.Кленин'            => make_author_info(email => KLENINS_EMAIL, git_author => 'А. Кленин'),
   'А. Кленин'           => make_author_info(email => KLENINS_EMAIL),
   'Александр С. Кленин' => make_author_info(email => KLENINS_EMAIL, git_author => 'A. Кленин'),
   'А. Шавлюгин'         => make_author_info,
   'В. Гринько'          => make_author_info,
   'В. Кевролетин'       => make_author_info,
   'В. Машенцев'         => make_author_info,
   'В. Степанец'         => make_author_info,
   'Г. Гренкин'          => make_author_info,
   'Е. Васильева'        => make_author_info,
   'Е. Иванова'          => make_author_info,
   'И. Бураго'           => make_author_info,
   'И. Лудов'            => make_author_info,
   'И. Олейников'        => make_author_info,
   'И. Туфанов'          => make_author_info,
   'Кленин А.'           => make_author_info(email => KLENINS_EMAIL, git_author => 'А. Кленин'),
   'Кленин А.С.'         => make_author_info(email => KLENINS_EMAIL, git_author => 'А. Кленин'),
   'Кленина Н. В.'       => make_author_info(git_author => 'Н. Кленина'),
   'М. Спорышев'         => make_author_info,
   'Н.В. Кленина'        => make_author_info(git_author => 'Н. Кленина'),
   'Н. В. Кленина'       => make_author_info(git_author => 'Н. Кленина'),
   'Н. Кленина'          => make_author_info(git_author => 'Н. Кленина'),
   'Н. Чистякова'        => make_author_info,
   'О. Бабушкин'         => make_author_info,
   'О.Ларькина'          => make_author_info(git_author => 'О. Ларькина'),
   'О. Ларькина'         => make_author_info,
   'О. Туфанов'          => make_author_info,
   'С. Пак'              => make_author_info,
   'C. Пак'              => make_author_info,
   'Туфанов И.'          => make_author_info(git_author => 'И. Туфанов'),
);

sub get_git_author_info {
   my ($author) = @_;
   my $git_author =
         exists $authors_map{$author}
      ? (exists $authors_map{$author}{git_author} ? $authors_map{$author}{git_author} : $author)
      : EXTERNAL_AUTHOR;
   my $email = exists $authors_map{$author} ? $authors_map{$author}{email} : DEFAULT_EMAIL;
   return ($git_author, $email);
}


1;