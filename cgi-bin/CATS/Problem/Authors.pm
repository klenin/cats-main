package CATS::Problem::Authors;

use strict;
use warnings;

BEGIN {
    use Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(get_git_author_info KLENINS_EMAIL DEFAULT_EMAIL DEFAULT_AUTHOR EXTERNAL_AUTHOR);
}

use constant {
    KLENINS_EMAIL   => 'klenin@gmail.com',
    DEFAULT_EMAIL   => 'unknown@example.com',
    DEFAULT_AUTHOR  => 'Unknown Author',
    EXTERNAL_AUTHOR => 'external'
};

sub make_author_info
{
    my ($h) = @_;
    my $res = {email => (defined $h->{email} ? $h->{email} : DEFAULT_EMAIL)};
    $res->{git_author} = $h->{git_author} if defined $h->{git_author};
    return $res;
}

my %authors_map = (
    'A. Klenin'           => {email => KLENINS_EMAIL},
    'А. Zhuplev'          => {git_author => 'A. Zhuplev'},
    'A. Zhuplev'          => {},
    'A. Maksimov'         => {},
    'Andrew Stankevich'   => {git_author => 'A. Stankevich'},
    'B. Vasilyev'         => {},
    'D. Vikharev'         => {},
    'E. Vasilyeva'        => {},
    'Elena Kryuchkova'    => {git_author => 'E. Kryuchkova'},
    'Georgiy Korneev'     => {git_author => 'G. Korneev'},
    'I. Ludov'            => {},
    'I. Tuphanov'         => {},
    'I. Tufanov'          => {git_author => 'I. Tuphanov'},
    'I. Burago'           => {},
    'Ludov I. Y.'         => {git_author => 'I. Ludov'},
    'Michail Mirzayanov'  => {git_author => 'M. Mirzayanov'},
    'Nick Durov'          => {git_author => 'N. Durov'},
    'T.Chistyakov'        => {},
    'T. Chistyakov'       => {},
    'Roman Elizarov'      => {git_author => 'R. Elizarov'},
    'А. Жуплев'           => {},
    'А. Зенкина'          => {},
    'А.Кленин'            => {email => KLENINS_EMAIL, git_author => 'А. Кленин'},
    'А. Кленин'           => {email => KLENINS_EMAIL},
    'Александр С. Кленин' => {email => KLENINS_EMAIL, git_author => 'A. Кленин'},
    'А. Шавлюгин'         => {},
    'В. Гринько'          => {},
    'В. Кевролетин'       => {},
    'В. Машенцев'         => {},
    'В. Степанец'         => {},
    'Г. Гренкин'          => {},
    'Е. Васильева'        => {},
    'Е. Иванова'          => {},
    'И. Бураго'           => {},
    'И. Лудов'            => {},
    'И. Олейников'        => {},
    'И. Туфанов'          => {},
    'Кленин А.'           => {email => KLENINS_EMAIL, git_author => 'А. Кленин'},
    'Кленин А.С.'         => {email => KLENINS_EMAIL, git_author => 'А. Кленин'},
    'Кленина Н. В.'       => {git_author => 'Н. Кленина'},
    'М. Спорышев'         => {},
    'Н.В. Кленина'        => {git_author => 'Н. Кленина'},
    'Н. В. Кленина'       => {git_author => 'Н. Кленина'},
    'Н. Кленина'          => {git_author => 'Н. Кленина'},
    'Н. Чистякова'        => {},
    'О. Бабушкин'         => {},
    'О.Ларькина'          => {git_author => 'О. Ларькина'},
    'О. Ларькина'         => {},
    'О. Туфанов'          => {},
    'С. Пак'              => {},
    'C. Пак'              => {},
    'Туфанов И.'          => {git_author => 'И. Туфанов'},
);

$_ = make_author_info($_) for values %authors_map;

sub get_git_author_info
{
    my ($author) = @_;
    my $a = $authors_map{$author} // {git_author => EXTERNAL_AUTHOR, email => DEFAULT_EMAIL};
    return ($a->{git_author} // $author, $a->{email});
}

1;
