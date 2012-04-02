package CATS::Data;
use strict;
use warnings;

use Encode;

use CATS::DB;
use CATS::Misc qw($cid $is_jury $is_root $uid);
use CATS::Utils qw(state_to_display);

BEGIN
{
    use Exporter;
    our @ISA = qw(Exporter);

    our @EXPORT = qw(
        get_registered_contestant
        enforce_request_state
        is_jury_in_contest
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


1;
