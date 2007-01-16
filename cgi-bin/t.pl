
use strict;

use lib '.';

use CATS::Misc qw(:all);

sql_connect;

my $sth = $dbh->prepare(q~
SELECT CP.id AS cpid, P.id AS pid,
CP.code || ' - ' || P.title AS problem_name, OC.title AS contest_name,
(SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = 10 AND D.account_id = ?) AS accepted_count,
(SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = 11 AND D.account_id = ?) AS wrong_answer_count,
(SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = 13 AND D.account_id = ?) AS time_limit_count,
P.contest_id - CP.contest_id AS is_linked, CP.status,
OC.id AS original_contest_id, CP.status,
CATS_DATE(P.upload_date) AS upload_date,
(SELECT A.login FROM accounts A WHERE A.id = P.last_modified_by) AS last_modified_by
FROM problems P, contest_problems CP, contests OC
WHERE CP.problem_id = P.id AND OC.id = P.contest_id AND CP.contest_id = ?
ORDER BY 6 DESC~);

$sth->execute(577647, 2, 2, 2, 2);

while (my (@a) = $sth->fetchrow_array()) {
  print @a, "\n";
}