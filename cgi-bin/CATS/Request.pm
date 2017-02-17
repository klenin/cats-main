package CATS::Request;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;

use Exporter qw(import);

our @EXPORT = qw(
    enforce_state
);

# Set request state manually. May be also used for retesting.
# Params: request_id, state, failed_test, testsets, points, judge_id.
sub enforce_state {
    my %p = @_;
    defined $p{state} && $p{request_id} or die;
    $dbh->do(q~
        UPDATE reqs
            SET failed_test = ?, state = ?, testsets = ?,
                points = ?, received = 0, result_time = CURRENT_TIMESTAMP, judge_id = ?
            WHERE id = ?~, undef,
        $p{failed_test}, $p{state}, $p{testsets}, $p{points}, $p{judge_id}, $p{request_id}
    ) or return;
    # Save log for ignored requests.
    if ($p{state} != $cats::st_ignore_submit) {
        $dbh->do(q~
            DELETE FROM log_dumps WHERE req_id = ?~, undef,
            $p{request_id}
        ) or return;
    }
    $dbh->commit;
    return 1;
}

1;
