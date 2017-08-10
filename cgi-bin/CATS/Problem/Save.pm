package CATS::Problem::Save;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($t $cid $uid $contest);
use CATS::Messages qw(msg);
use CATS::Output qw(url_f);
use CATS::ProblemStorage;
use CATS::StaticPages;
use CATS::Web qw(param save_uploaded_file);

sub add_problem_to_contest {
    my ($pid, $problem_code) = @_;
    CATS::StaticPages::invalidate_problem_text(cid => $cid);
    $dbh->selectrow_array(q~
        SELECT 1 FROM contest_problems WHERE contest_id = ? and problem_id = ?~, undef,
        $cid, $pid) and return msg(1003);
    $dbh->do(q~
        INSERT INTO contest_problems(id, contest_id, problem_id, code, status)
            VALUES (?, ?, ?, ?, ?)~, {},
        new_id, $cid, $pid, $problem_code,
        # If non-archive contest is in progress, hide newly added problem immediately.
        $contest->{time_since_start} > 0 && $contest->{ctype} == 0 ?
            $cats::problem_st_hidden : $cats::problem_st_ready);
}

sub problems_link_save {
    my $pid = param('problem_id')
        or return msg(1012);

    my $problem_code;
    if (!$contest->is_practice) {
        $problem_code = param('problem_code');
        cats::is_good_problem_code($problem_code) or return msg(1134);
    }
    my $title = $dbh->selectrow_array(q~
        SELECT title FROM problems WHERE id = ?~, undef,
        $pid) or return msg(1012);
    my $move_problem = param('move');
    if ($move_problem) {
        # Jury account in the problem's origin contest is required.
        # Check beforehand to avoid need for rollback.
        my ($j) = $dbh->selectrow_array(q~
            SELECT CA.is_jury FROM contest_accounts CA
                INNER JOIN contests C ON CA.contest_id = C.id
                INNER JOIN problems P ON C.id = P.contest_id
            WHERE CA.account_id = ? AND P.id = ?~, undef,
            $uid, $pid);
        $j or return msg(1135, $title);
    }
    add_problem_to_contest($pid, $problem_code) or return;
    if ($move_problem) {
        $dbh->do(q~
            UPDATE problems SET contest_id = ? WHERE id = ?~, undef,
            $cid, $pid);
        msg(1021, $title);
    }
    else {
        msg(1001, $title);
    }
    $dbh->commit;
}

sub set_problem_import_diff {
    my ($pid, $sha) = @_;
    $t->param(problem_import_diff => {
        sha => $sha,
        abbreviated_sha => substr($sha, 0, 8),
        href_commit => url_f('problem_history', pid => $pid, h => $sha, a => 'commitdiff'),
    });
}

sub problems_replace {
    my $pid = param('problem_id')
        or return msg(1012);
    my $file = param('zip') || '';
    $file =~ /\.(zip|ZIP)$/
        or return msg(1053);
    my ($contest_id, $old_title, $repo) = $dbh->selectrow_array(q~
        SELECT contest_id, title, repo FROM problems WHERE id = ?~, undef,
        $pid);
    # Forbid replacing linked problems. Firstly for robustness,
    # secondly for security -- to avoid checking is_jury($contest_id).
    $contest_id == $cid
        or return msg(1117, $old_title);

    my CATS::ProblemStorage $p = CATS::ProblemStorage->new;
    return if CATS::ProblemStorage::get_repo($pid, undef, 1, logger => CATS::ProblemStorage->new)->is_remote;

    my $fname = save_uploaded_file('zip');

    $p->{old_title} = $old_title unless param('allow_rename');
    my ($error, $result_sha) = $p->load(
        CATS::Problem::Source::Zip->new($fname, $p), $cid, $pid, 1, $repo, param('message'), param('is_amend'));
    $t->param(problem_import_log => $p->encoded_import_log());
    #unlink $fname;
    if ($error) {
        $dbh->rollback;
        return msg(1008);
    }
    set_problem_import_diff($pid, $result_sha);
    $dbh->commit;
    CATS::StaticPages::invalidate_problem_text(pid => $pid);
    msg(1007);
}

sub problems_add {
    my ($source_name, $is_remote) = @_;
    my $problem_code;
    if (!$contest->is_practice) {
        ($problem_code) = $contest->unused_problem_codes
            or return msg(1017);
    }

    my CATS::ProblemStorage $p = CATS::ProblemStorage->new;
    my ($error, $result_sha, $problem) = $is_remote
              ? $p->load(CATS::Problem::Source::Git->new($source_name, $p), $cid, new_id, 0, $source_name)
              : $p->load(CATS::Problem::Source::Zip->new($source_name, $p), $cid, new_id, 0, undef);
    $t->param(problem_import_log => $p->encoded_import_log());
    $error ||= !add_problem_to_contest($problem->{id}, $problem_code);

    if (!$error) {
        $dbh->commit;
        set_problem_import_diff($problem->{id}, $result_sha);
    } else {
        $dbh->rollback;
        msg(1008);
    }
}

sub problems_add_new {
    my $file = param('zip') || '';
    $file =~ /\.(zip|ZIP)$/
        or return msg(1053);
    my $fname = save_uploaded_file('zip');
    problems_add($fname, 0);
    unlink $fname;
}

sub problems_add_new_remote {
    my $url = param('remote_url') || '';
    $url or return msg(1091);
    problems_add($url, 1);
}

1;
