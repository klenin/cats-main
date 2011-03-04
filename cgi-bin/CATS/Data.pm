package CATS::Data;
use strict;
use warnings;

use Encode;
use CGI ();

use CATS::DB;
use CATS::Misc qw(:all);
use CATS::Utils qw(state_to_display);
use CATS::Contest;
use CATS::IP;

BEGIN
{
    use Exporter;
    our @ISA = qw(Exporter);

    our @EXPORT = qw(
        get_registered_contestant
        enforce_request_state
        get_sources_info
        is_jury_in_contest
        get_judge_name
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
# Параметры: request_id, state, failed_test, testsets.
sub enforce_request_state
{
    my %p = @_;
    defined $p{state} or return;
    $dbh->do(qq~
        UPDATE reqs
            SET failed_test = ?, state = ?, testsets = ?,
                points = NULL, received = 0, result_time = CURRENT_TIMESTAMP, judge_id = NULL
            WHERE id = ?~, {},
        $p{failed_test}, $p{state}, $p{testsets}, $p{request_id}
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
    my $rid = $p{request_id} or return;

    my @req_ids = ref $rid eq 'ARRAY' ? @$rid : ($rid);
    @req_ids = map +$_, grep $_ && /^\d+$/, @req_ids;
    @req_ids or return;

    my $src = $p{get_source} ? ' S.src, DE.syntax,' : '';

    # SELECT ... WHERE ... req_id IN (1,2,3) тормозит в Firebird 1.5,
    # поэтому выполяем цикл вручную.
    my $c = $dbh->prepare(qq~
        SELECT
            S.req_id,$src S.fname AS file_name,
            R.account_id, R.contest_id, R.problem_id, R.judge_id,
            R.state, R.failed_test,
            R.submit_time,
            R.test_time,
            R.result_time,
            DE.description AS de_name,
            A.team_name, A.last_ip,
            P.title AS problem_name,
            C.title AS contest_name,
            COALESCE(R.testsets, CP.testsets) AS testsets,
            C.id AS contest_id, CP.id AS cp_id
        FROM sources S
            INNER JOIN reqs R ON R.id = S.req_id
            INNER JOIN default_de DE ON DE.id = S.de_id
            INNER JOIN accounts A ON A.id = R.account_id
            INNER JOIN problems P ON P.id = R.problem_id
            INNER JOIN contests C ON C.id = R.contest_id
            INNER JOIN contest_problems CP ON CP.contest_id = C.id AND CP.problem_id = P.id
        WHERE req_id = ?~);
    my $result = [];
    for (@req_ids)
    {
        my $row = $c->execute($_) && $c->fetchrow_hashref or return;
        $c->finish;
        push @$result, $row;
    }

    my $official = $p{get_source} && !$is_jury && CATS::Contest::current_official;
    for my $r (@$result)
    {
        @$r{qw(last_ip_short last_ip)} =
            CATS::IP::short_long(CATS::IP::filter_ip($r->{last_ip}));
        # Только часы и минуты от времени начала и окончания обработки.
        ($r->{"${_}_short"} = $r->{$_}) =~ s/^(.*)\s+(\d\d:\d\d)\s*$/$2/
            for qw(test_time result_time);
        #$r->{src} =~ s/</&lt;/;
        $r = {
            %$r, state_to_display($r->{state}),
            href_stats => url_f('user_stats', uid => $r->{account_id}),
        };
        get_nearby_attempt($r, 'prev', '<', 'DESC', 1);
        get_nearby_attempt($r, 'next', '>', 'ASC', 0);
        # Во время официального турнира запретить просмотр исходного кода из других турниров,
        # чтобы не допустить списывания.
        if ($official && $official->{id} != $r->{contest_id})
        {
            $r->{src} = res_str(123, $official->{title});
        }
    }

    return ref $rid ? $result : $result->[0];
}

sub get_nearby_attempt
{
    my ($si, $prevnext, $cmp, $ord, $diff) = @_;
    my $na = $dbh->selectrow_hashref(qq~
        SELECT id, submit_time FROM reqs
          WHERE account_id = ? AND problem_id = ? AND id $cmp ?
          ORDER BY id $ord ROWS 1~, { Slice => {} },
        $si->{account_id}, $si->{problem_id}, $si->{req_id}
    ) or return;
    for ($na->{submit_time})
    {
        s/\s*$//;
        # Если дата совпадает с текущей попыткой, выводим только время
        my ($n_date, $n_time) = /^(\d+\.\d+\.\d+\s+)(.*)$/;
        $si->{"${prevnext}_attempt_time"} = $si->{submit_time} =~ /^$n_date/ ? $n_time : $_;
    }
    my $f = CGI::url_param('f') || 'run_log';
    my @p;
    if ($f eq 'diff_runs')
    {
        for (1..2)
        {
            my $r = CGI::url_param("r$_") || 0;
            push @p, "r$_" => ($r == $si->{req_id} ? $na->{id} : $r);
        }
    }
    else
    {
        @p = (rid => $na->{id});
    }
    $si->{"href_${prevnext}_attempt"} = url_f($f, @p);
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


1;
