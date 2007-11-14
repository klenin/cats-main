package CATS::Data;
use strict;
use warnings;

use Encode;
use CGI ();

use CATS::DB;
use CATS::Misc qw(:all);

BEGIN
{
    use Exporter;
    our @ISA = qw(Exporter);

    our @EXPORT = qw(
        get_registered_contestant
        enforce_request_state
        get_sources_info
        insert_ooc_user
        is_jury_in_contest
        get_judge_name
        get_contests_info
    );

    our %EXPORT_TAGS = (all => [ @EXPORT ]);
}


# Получить информацию об участнике турнира.
# параметры: fields, contest_id, account_id.
sub get_registered_contestant
{
    my %p = @_;
    $p{fields} ||= 1;
    $p{account_id} ||= $uid or return;
    $p{contest_id} or die;
    
    $dbh->selectrow_array(qq~
        SELECT $p{fields} FROM contest_accounts WHERE contest_id = ? AND account_id = ?~, undef,
        $p{contest_id}, $p{account_id});
}


sub is_jury_in_contest
{
    my %p = @_;
    return 1 if $is_root;
    # Оптимизация: если запрос о текущем турнире, вывести уже считанное значение.
    if (defined $cid && $p{contest_id} == $cid)
    {
        return $is_jury;
    }
    my ($j) = get_registered_contestant(fields => 'is_jury', @_);
    return $j;
}


# Вручную прописать результат попытки участника. Также можно применять для повторного тестирования.
# Параметры: request_id, state, failed_test.
sub enforce_request_state
{
    my %p = @_;
    defined $p{state} or return;
    $dbh->do(qq~
        UPDATE reqs
            SET failed_test = ?, state = ?, 
                points = NULL, received = 0, result_time = CATS_SYSDATE(), judge_id = NULL 
            WHERE id = ?~, {},
        $p{failed_test}, $p{state}, $p{request_id}
    ) or return;
    if ($p{state} != $cats::st_ignore_submit) # сохраняем лог игнорируемых попыток
    {
        $dbh->do(qq~DELETE FROM log_dumps WHERE req_id = ?~, {}, $p{request_id})
            or return;
    }
    $dbh->commit;
    return 1;
}


# Получить информацию об исходном тексте одной или нескольких попыток.
# Параметры: request_id.
sub get_sources_info
{
    my %p = @_;
    
    defined $p{request_id} or return;
    
    my $req_id_list;
    if (ref $p{request_id} eq 'ARRAY')
    {
        my @req_ids = grep defined $_ && $_ > 0, @{$p{request_id}}
            or return;

        $req_id_list = join ',', map sprintf('%d', $_), @req_ids;
    }
    else
    {
        $req_id_list = $p{request_id};
    }
    
    $req_id_list or return;
    
    my $src = $p{get_source} ? ' S.src,' : '';

    my $result = $dbh->selectall_arrayref(qq~
        SELECT
            S.req_id, $src S.fname AS file_name,
            R.account_id, R.contest_id, R.problem_id, R.judge_id,
            R.state, R.failed_test,
            CATS_DATE(R.submit_time) AS submit_time,
            CATS_DATE(R.test_time) AS test_time,
            CATS_DATE(R.result_time) AS result_time,
            DE.description AS de_name,
            A.team_name,
            P.title AS problem_name,
            C.title AS contest_name,
            CP.testsets
        FROM sources S
            INNER JOIN reqs R ON R.id = S.req_id
            INNER JOIN default_de DE ON DE.id = S.de_id
            INNER JOIN accounts A ON A.id = R.account_id
            INNER JOIN problems P ON P.id = R.problem_id
            INNER JOIN contests C ON C.id = R.contest_id
            INNER JOIN contest_problems CP ON CP.contest_id = C.id AND CP.problem_id = P.id
        WHERE req_id IN ($req_id_list)~, { Slice => {} }
    ) or return;
    
    for my $r (@$result)
    {
        # Только минуты от времени начала и окончания обработки.
        ($r->{"${_}_short"} = $r->{$_}) =~ s/^(.*)\s+(\d\d:\d\d)\s*$/$2/
            for qw(test_time result_time);
        #$r->{src} =~ s/</&lt;/;
        $r = { %$r, state_to_display($r->{state}) };
        get_nearby_attempt($r, 'prev', '<', 'DESC', 1);
        get_nearby_attempt($r, 'next', '>', 'ASC', 0);
    }

    return ref $p{request_id} ? $result : $result->[0];
}

sub get_nearby_attempt
{
    my ($si, $prevnext, $cmp, $ord, $diff) = @_;
    my $na = $dbh->selectrow_hashref(qq~
        SELECT FIRST 1 id, CATS_DATE(submit_time) AS submit_time FROM reqs
          WHERE account_id = ? AND problem_id = ? AND id $cmp ?
          ORDER BY id $ord~, { Slice => {} },
        $si->{account_id}, $si->{problem_id}, $si->{req_id}
    ) or return;
    for ($na->{submit_time})
    {
        s/\s*$//;
        # Если дата совпадает с текущей попыткой, выводим только время
        my ($n_date, $n_time) = /^(\d+\-\d+\-\d+\s+)(.*)$/;
        $si->{"${prevnext}_attempt_time"} = $si->{submit_time} =~ /^$n_date/ ? $n_time : $_;
    }
    $si->{"href_${prevnext}_attempt"} = url_f(CGI::url_param('f') || 'run_log', rid => $na->{id});
    $si->{href_diff_runs} = url_f('diff_runs', r1 => $na->{id}, r2 => $si->{req_id}) if $diff;
}


sub get_judge_name
{
    my ($judge_id) = @_
        or return;
    my ($name) = $dbh->selectrow_array(qq~
      SELECT nick FROM judges WHERE id = ?~,
      {}, $judge_id);
    return $name;
}


sub insert_ooc_user
{
    my %p = @_;
    $p{contest_id} ||= $cid or return;
    $dbh->do(qq~
        INSERT INTO contest_accounts (
            id, contest_id, account_id, is_jury, is_pop, is_hidden, is_ooc, is_remote,
            is_virtual, diff_time
        ) VALUES(?,?,?,?,?,?,?,?,?,?)~, {},
        new_id, $p{contest_id}, $p{account_id}, 0, 0, 0, 1, $p{is_remote} || 0,
        0, 0
    );
}


sub get_contests_info
{
    my ($contest_list, $uid) = @_;
    $uid ||= 0;

    my $frozen = 0;
    my $not_started = 0;
    my $title_prefix;
    my $show_points = undef;
    my $sth = $dbh->prepare(qq~
        SELECT C.title,
          CATS_SYSDATE() - C.freeze_date,
          CATS_SYSDATE() - C.defreeze_date,
          CATS_SYSDATE() - C.start_date,
          (SELECT COUNT(*) FROM contest_accounts WHERE contest_id = C.id AND account_id = ?),
          C.rules
        FROM contests C
        WHERE id IN ($contest_list)~
    );
    $sth->execute($uid);
    while (my (
        $title, $since_freeze, $since_defreeze, $since_start, $registered, $rules) = $sth->fetchrow_array)
    {
        $frozen ||= $since_freeze > 0 && $since_defreeze < 0;
        $not_started ||= $since_start < 0 && !$registered;
        $show_points ||= $rules;
        $title = Encode::decode_utf8($title);
        for ($title_prefix)
        {
            $_ = $title, last if !defined $_;
            my $i = 0;
            while (
                $i < length($_) && $i < length($title) &&
                substr($_, $i, 1) eq substr($title, $i, 1)
            )
            {
                $i++;
            }
            $_ = substr($_, 0, $i);
        }
    }
    return ($title_prefix || '', $frozen, $not_started, $show_points);
}

1;
