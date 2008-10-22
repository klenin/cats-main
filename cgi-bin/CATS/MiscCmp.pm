# создаем таблички результатов сравнения программ
# Предполагается, что уже создан массив @titles заголовков и хеш %srcfiles имён tmp-файлов
sub generate_table
{
    my ($titles_ref, $srcfiles_ref, $pid, $limit) = @_;
    my @titles = @$titles_ref;
    my %srcfiles = %$srcfiles_ref;

    my @rows;
    my $deleted;
    while (@titles)
    {
        my $rid1 = $titles[0]{rid};
        my $team1 = $titles[0]{id};
        my %cur_row = (id =>  $team1);
        my @cells;
        if (!$limit)
        {
            push @cells, undef foreach (1..$deleted);
        }
        
        foreach (@titles)
        {
            my $rid2 = $$_{rid};
            my $value = CATS::Diff::cmp_diff($srcfiles{$rid1},$srcfiles{$rid2});            #CATS::Diff::cmp_advanced($srcfiles{$title1},$srcfiles{$title2});
            my %cell = (
                value => $value,
                href => url_f('cmp', rid1 => $rid1, rid2 => $rid2, pid => $pid),
                diff_href => url_f('diff_runs', r1 => $rid1, r2 => $rid2),
                team1 => $team1,
                team2 => $$_{id}
            );          
            
            $cell{value}>=80 and $cell{alert}=1;
            push @cells, \%cell if (!$limit || $value>=$limit);
        }
        %cur_row = (%cur_row, cells => \@cells);                
        push @rows, \%cur_row;
        `del $srcfiles{$rid1}`;
        shift @titles;
        $deleted++;
    }
    
    @rows;
}


# формирует запрос для построения таблицы выбора задачи, вместе с размером
# выходной таблицы
sub generate_count_query
{
    my ($contest, $teams, $vers) = @_;

    my $query =
        q~SELECT
            P.id,
            P.title,~;
    $contest ne 'all' and
    $query .=q~             C.id,
            C.title,~
    or $query .= 'NULL, NULL,';
    
    $contest == 500001 and $query .= 'NULL '
    or $query .= '('.generate_cmp_query($contest, $teams, $vers,1).')';
    
    $query .=
        q~FROM
            problems P,
            contests C,
            contest_problems CP
        WHERE
            CP.problem_id = P.id and
            CP.contest_id = C.id ~;
    !$contest || $contest ne 'all' and $query .= "AND C.id = $contest ";
    $query .= q~GROUP BY C.id, P.id, P.title, C.title ~;
    $query;    
}


# формирование запроса на сравнение
sub generate_cmp_query
{
    my ($contest, $teams, $vers, $count) = @_;
        
    my $query = 'SELECT ';
    if (defined ($count))
    {
        $query .= 'count(';
        $vers eq 'last' || !$vers and $query .= 'DISTINCT ';
        $query .= 'A.id) ';
    }
    else
    {
        $query .= 'A.team_name, A.id, ';
        $vers eq 'all' and $query .= 'R.id ' or $query .='max(R.id) '; # все версии или только последние
    }
    
    $query .= q~FROM ACCOUNTS A, SOURCES  S, REQS    R ~;
    
    ($teams eq 'all' or $contest eq 'all') and $query .= 'WHERE ' or
    $query .= q~, CONTEST_ACCOUNTS CA  WHERE CA.account_id = A.id AND ~ and
    (!$teams || $teams eq 'incontest') and                 # только команды-участники
    $query .=q~ CA.is_ooc=0 AND CA.is_remote=0 AND ~ or
    $teams eq 'ooc' and
    $query .=q~ CA.is_ooc=1 AND CA.is_remote=1 AND ~;         # только команды ooc

    $count and $query .= 'R.problem_id = P.id AND ' or $query .= 'R.problem_id = ? AND ';
    $query .=q~ R.account_id = A.id AND S.req_id = R.id AND S.de_id in (7,102,3016) AND R.state <> ~.$cats::st_compilation_error ;
    $contest ne 'all' and $query .= " AND R.contest_id = ".$contest;
    $vers ne 'all' && !defined($count) and $query .=' GROUP BY A.team_name, A.id';
    !$count and $query .= " ORDER BY A.team_name";

    $query;
}
