package CATS::Contest;

use strict;
use warnings;

use CGI qw(:standard);
use Encode ();
use YAML::Syck ();

use lib '..';
use CATS::DB;
use CATS::Misc qw(:all);
use CATS::RankTable;


sub get_names
{
    use bytes;
    map Encode::decode('KOI8-R', $_) =>
        'Районная олимпиада', 'Городская олимпиада', 'Краевая олимпиада',
        'ЛШ олимпиада', 'Заочная олимпиада', 'Школьники ACM', 'Весенний турнир',
        'Муниципальная олимпиада',
}


sub personal_official_results
{
    init_template('main_official_results.htm');
    my @names = get_names();
    my $contests = $dbh->selectall_arrayref(q~
        SELECT id, title FROM contests
        WHERE
            (is_hidden = 0 OR is_hidden IS NULL) AND
            defreeze_date < CURRENT_DATE AND (~ .
            join(' OR ' => map 'title LIKE ?' => @names) . q~) ORDER BY start_date DESC~,
        { Slice => {} }, map "$_ %", @names);

    my $search = Encode::decode_utf8(param('search'));
    my $results;
    my $group_by_type = (url_param('group') || '') eq 'type';
    for (@$contests)
    {
        my ($name, $year, $rest) = $_->{title} =~ m/^(.*)\s(\d{4})(.*)/
            or die $_->{name};
        # чтобы YAML не скатывался на backslash escaping
        $name = Encode::decode_utf8($name);
        # отбрасываем пробные туры
        !$rest || $rest =~ m/^\s*[I\d]/ or next;
        ($year, $name) = ($name, $year) if $group_by_type;
        push @{$results->{$year}->{$name}}, $_->{id};
    }
    
    for my $i (values %$results)
    {
        for my $j (values %$i)
        {
            my $found = [];
            if ($search)
            {
                $YAML::Syck::ImplicitUnicode = 1;
                my $clist = join ',', @$j;
                my $cache_file = cats_dir() . "./rank_cache/r/$clist";
                unless (-f $cache_file)
                {
                    my $rt = CATS::RankTable->new;
                    $rt->{hide_ooc} = 1;
                    $rt->{hide_virtual} = 1;
                    $rt->{use_cache} = 0;
                    $rt->{contest_list} = $clist;
                    $rt->get_contests_info;
                    $rt->rank_table;
                    my $short_rank = [
                        map {{ team_name => $_->{team_name}, place => $_->{place} }} @{$rt->{rank}}
                    ];
                    YAML::Syck::DumpFile($cache_file, $short_rank);
                }
                my $short_rank = YAML::Syck::LoadFile($cache_file);
                for (@$short_rank)
                {
                    push @$found, $_ if $_->{team_name} =~ m/\Q$search\E/i;
                }
            }
            $j = { cids => $j, found => $found };
        }
    }

    init_template('main_official_results.htm');
    $t->param(results => YAML::Syck::Dump($results));
}


1;
