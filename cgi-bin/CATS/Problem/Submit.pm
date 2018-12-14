package CATS::Problem::Submit;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::DevEnv;
use CATS::Globals qw($cid $contest $is_jury $t $uid $user);
use CATS::Messages qw(msg);
use CATS::Output qw(url_f);
use CATS::Request;

sub _get_submit_uid {
    my ($p) = @_;
    if ($is_jury && $p->{submit_as}) {
        return scalar $dbh->selectrow_array(q~
            SELECT A.id FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id
            WHERE CA.contest_id = ? AND A.login = ?~, undef,
            $cid, $p->{submit_as}) || msg(1139, $p->{submit_as});
    }
    $uid // ($contest->is_practice ? $user->{anonymous_id} : die);
}

sub too_frequent {
    my ($submit_uid) = @_;
    # Protect from Denial of Service -- disable too frequent submissions.
    my $prev = $dbh->selectcol_arrayref(q~
        SELECT CAST(CURRENT_TIMESTAMP - R.submit_time AS DOUBLE PRECISION) FROM reqs R
        WHERE R.account_id = ?
        ORDER BY R.submit_time DESC
        ROWS 2~, {},
        $submit_uid);
    my $SECONDS_PER_DAY = 24 * 60 * 60;
    ($prev->[0] || 1) < 3/$SECONDS_PER_DAY ||
    ($prev->[1] || 1) < 20/$SECONDS_PER_DAY;
}

sub _determine_state {
    my ($p) = @_;
    return $cats::st_ignore_submit if $p->{ignore};
    !$is_jury && !$p->{np} && $CATS::Config::TB && $p->user_agent =~ /$CATS::Config::TB/ ?
        $cats::st_ignore_submit : $cats::st_not_processed;
}

sub _prepare_de {
    my ($p, $file, $cpid) = @_;

    my $did = $p->{de_id} or return msg(1013);
    if ($did eq 'by_extension') {
        my $de = CATS::DevEnv->new(CATS::JudgeDB::get_DEs({ active_only => 1 }))->by_file_extension($file)
            or return msg(1013);
        $did = $de->{id};
        $t->param(de_name => $de->{description});
    }
    my $allowed_des = $dbh->selectall_arrayref(q~
        SELECT CPD.de_id, D.description
        FROM contest_problem_des CPD
        INNER JOIN default_de D ON D.id = CPD.de_id
        WHERE cp_id = ? ORDER BY D.code~, { Slice => {} },
        $cpid);
    if ($allowed_des && @$allowed_des && 0 == grep $_->{de_id} == $did, @$allowed_des) {
        $t->param(de_not_allowed => $allowed_des);
        return;
    }
    $did;
}

sub problems_submit {
    my ($p) = @_;
    my $pid = $p->{problem_id} or return msg(1012);
    $user->{is_participant} or return msg(1116);

    # Use explicit empty string comparisons to avoid problems with solutions containing only '0'.
    my $file = $p->{source};
    my $source_text = $p->{source_text} // '';
    $file || $source_text ne '' or return msg(1009);
    !$file || $source_text eq '' or return msg(1042);
    !$file || length($file->remote_file_name) <= 200 or return msg(1010);
    if ($source_text eq '') {
        $source_text = $file->content;
        $source_text ne '' or return msg(1011);
    }

    $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM tests T
        WHERE T.problem_id = ? AND T.snippet_name IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM snippets S
            WHERE S.name = T.snippet_name AND S.problem_id = T.problem_id AND
                S.account_id = ? AND S.contest_id = ?)~, undef,
        $pid, $uid, $cid) and return msg(1168);

    my $contest_finished = $contest->has_finished_for($user);
    my ($cpid, $status, $title) = $dbh->selectrow_array(q~
        SELECT CP.id, CP.status, P.title
        FROM contest_problems CP
        INNER JOIN problems P ON P.id = CP.problem_id
        WHERE CP.contest_id = ? AND CP.problem_id = ?~, undef,
        $cid, $pid) or return msg(1012);

    unless ($is_jury) {
        $contest->has_started($user->{diff_time})
            or return msg(1080);
        !$contest_finished || $user->{is_virtual}
            or return msg(1081);
        $status //= $cats::problem_st_ready;
        return msg(1124, $title) if $status == $cats::problem_st_disabled;
        # Do not leak the title of a hidden problem.
        return msg(1124, '') if $status >= $cats::problem_st_hidden;

        # During the official contest, do not accept submissions for other contests.
        if (!$contest->{is_official} || $user->{is_virtual}) {
            my ($current_official) = $contest->current_official;
            !$current_official
                or return msg(1123, $current_official->{title});
        }
    }

    my $submit_uid = _get_submit_uid($p) or return;

    return msg(1131) if too_frequent($submit_uid);

    my $prev_reqs_count;
    if ($contest->{max_reqs} && !$is_jury && !$user->{is_virtual}) {
        my @excluded_verdicts = split /,/, $contest->{max_reqs_except} // '';
        $prev_reqs_count = $dbh->selectrow_array(_u $sql->select('reqs', 'COUNT(*)', {
            account_id => $submit_uid,
            problem_id => $pid,
            contest_id => $cid,
            state => { -not_in => \@excluded_verdicts },
        }));

        return msg(1137) if $prev_reqs_count >= $contest->{max_reqs};
    }

    my $did = _prepare_de($p, $file ? $file->remote_file_name : '', $cpid) or return;

    # Forbid repeated submissions of the identical code with the same DE.
    my $source_hash = CATS::Utils::source_hash($source_text);
    my ($same_source, $prev_submit_time) = $dbh->selectrow_array(q~
        SELECT S.req_id, R.submit_time
        FROM sources S INNER JOIN reqs R ON S.req_id = R.id
        WHERE
            R.account_id = ? AND R.problem_id = ? AND
            R.contest_id = ? AND S.hash = ? AND S.de_id = ?
        ROWS 1~, undef,
        $submit_uid, $pid, $cid, $source_hash, $did);
    $same_source and return msg(1132, $prev_submit_time);

    my $rid = CATS::Request::insert($pid, $cid, $submit_uid,
        [ CATS::DevEnv->new(CATS::JudgeDB::get_DEs())->bitmap_by_ids($did) ],
        { state => _determine_state($p) });

    my $s = $dbh->prepare(q~
        INSERT INTO sources(req_id, de_id, src, fname, hash) VALUES (?, ?, ?, ?, ?)~);
    $s->bind_param(1, $rid);
    $s->bind_param(2, $did);
    $s->bind_param(3, $source_text, { ora_type => 113 } ); # blob
    $s->bind_param(4, $file ? $file->remote_file_name :
        "$rid." . CATS::DevEnv->new(CATS::JudgeDB::get_DEs({ id => $did }))->default_extension($did));
    $s->bind_param(5, $source_hash);
    $s->execute;
    $dbh->commit;

    $t->param(solution_submitted => 1, href_run_details => url_f('run_details', rid => $rid));
    $contest_finished ? msg(1087) :
    defined $prev_reqs_count ? msg(1088, $contest->{max_reqs} - $prev_reqs_count - 1) :
    msg(1014);
    $rid;
}

sub problems_submit_std_solution {
    my ($p) = @_;
    my $pid = $p->{problem_id};

    defined $pid or return msg(1012);

    my ($title) = $dbh->selectrow_array(q~
        SELECT title FROM problems WHERE id = ?~, undef,
        $pid) or return msg(1012);

    my $sol_count = 0;

    my $c = $dbh->prepare(q~
        SELECT name, src, de_id, fname
        FROM problem_sources
        WHERE problem_id = ? AND (stype = ? OR stype = ?)~);
    $c->execute($pid, $cats::solution, $cats::adv_solution);

    my $de_list = CATS::DevEnv->new(CATS::JudgeDB::get_DEs());

    while (my ($name, $src, $did, $fname) = $c->fetchrow_array) {
        if (!$de_list->by_id($did)) {
            msg(1013);
            next;
        }
        my $rid = CATS::Request::insert($pid, $cid, $uid,
            [ $de_list->bitmap_by_ids($did) ], { state => _determine_state($p), tag => $name });

        my $s = $dbh->prepare(q~
            INSERT INTO sources(req_id, de_id, src, fname) VALUES (?, ?, ?, ?)~);
        $s->bind_param(1, $rid);
        $s->bind_param(2, $did);
        $s->bind_param(3, $src, { ora_type => 113 } ); # blob
        $s->bind_param(4, $fname);
        $s->execute;

        ++$sol_count;
    }

    $sol_count or return msg(1106, $title);
    $dbh->commit;
    msg(1107, $title, $sol_count);
}

1;
