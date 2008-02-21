package CATS::Contest;

use strict;
use warnings;

use CGI qw(:standard);
use Encode ();
use YAML::Syck ();

use lib '..';
use CATS::DB;
use CATS::Misc qw(:all);


sub get_names
{
    use bytes;
    map Encode::decode('KOI8-R', $_) =>
        'Районная олимпиада', 'Городская олимпиада', 'Краевая олимпиада',
        'ЛШ олимпиада', 'Заочная олимпиада', 'Школьники ACM', 'Весенний турнир';
}

use utf8;
sub personal_official_results
{
    init_template('main_official_results.htm');
    my @names = get_names();
    my $contests = $dbh->selectall_arrayref(q~
        SELECT id, title FROM contests
        WHERE
            (is_hidden = 0 OR is_hidden IS NULL) AND
            defreeze_date < CURRENT_DATE AND (~ .
            join(' OR ' => map 'title LIKE ?' => @names) . q~) ORDER BY start_date~,
        { Slice => {} }, map "$_ %", @names);

    my $results;
    my $group_by_type = (url_param('group') || '') eq 'type';
    for (@$contests)
    {
        my ($name, $year, $rest) = $_->{title} =~ m/^(.*)\s(\d{4})(.*)/
            or die $_->{name};
        # чтобы YAML не скатывался на backslash escaping
        $name = Encode::decode_utf8($name);
        # отбрасываем пробные туры
        !$rest || $rest =~ m/[I\d]/ or next;
        ($year, $name) = ($name, $year) if $group_by_type;
        push @{$results->{$year}->{$name}}, $_->{id};
    }
    $t->param(results => YAML::Syck::Dump($results));
}


1;
