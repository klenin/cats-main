package CATS::Problem::Save;

use strict;
use warnings;

use CATS::Contest;
use CATS::Contest::Participate qw(is_jury_in_contest);
use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($t $cid $uid $contest);
use CATS::Messages qw(msg);
use CATS::Output qw(url_f);
use CATS::Problem::Storage;
use CATS::StaticPages;
use CATS::Web qw(param save_uploaded_file);


sub _get_cpid {
    my ($contest_id, $problem_id) = @_;
    $dbh->selectrow_array(q~
        SELECT id FROM contest_problems WHERE contest_id = ? and problem_id = ?~, undef,
        $contest_id, $problem_id);
}

sub _contest_is_practice {
    my ($contest_id) = @_;
    return $contest->is_practice if $contest_id == $cid;
    $dbh->selectrow_array(q~
        SELECT ctype FROM contests WHERE id = ?~, undef,
        $contest_id) ? 1 : 0;
}

sub _add_problem_to_contest {
    my ($contest_id, $pid, $code) = @_;
    my $target_contest = $contest_id == $cid ? $contest :
        CATS::Contest->new->load($contest_id, [ 'ctype', CATS::Contest::time_since_sql('start') ]);

    $target_contest->is_practice || defined $code or return msg(1134);
    CATS::StaticPages::invalidate_problem_text(cid => $contest_id);
    $dbh->do(_u $sql->insert(contest_problems => {
        id => new_id, contest_id => $contest_id, problem_id => $pid, code => $code,
        # If non-archive contest is in progress, hide newly added problem immediately.
        status => ($target_contest->has_started && !$target_contest->is_practice ?
            $cats::problem_st_hidden : $cats::problem_st_ready)
    })) or msg(1129);
}

sub _prepare_move {
    my ($pid, $to_contest) = @_;
    $pid or return msg(1012);
    is_jury_in_contest(contest_id => $to_contest) or return msg(1135);
    my $problem = $dbh->selectrow_hashref(q~
        SELECT P.title, P.contest_id, C.is_hidden, CP.status, C.show_packages
        FROM problems P
        INNER JOIN contests C ON C.id = P.contest_id
        INNER JOIN contest_problems CP ON C.id = P.contest_id
        WHERE P.id = ?~, { Slice => {} },
        $pid) or return msg(1012);
    $problem;
}

sub link_problem {
    my ($pid, $code, $to_contest) = @_;

    my $problem = _prepare_move($pid, $to_contest) or return;

    if (!is_jury_in_contest(contest_id => $problem->{contest_id})) {
        # Return 'not found' error instead of 'no access' to avoid leaking problem id.
        return msg(1012) if $problem->{is_hidden} || $problem->{status} >= $cats::problem_st_hidden;
        $problem->{show_packages} || CATS::Contest::Participate::all_sites_finished($problem->{contest_id})
            or return msg(1012);
    }

    _get_cpid($to_contest, $pid) and return msg(1003);
    _add_problem_to_contest($to_contest, $pid, $code) or return;
    $dbh->commit;
    msg(1001, $problem->{title});
    1;
}

sub move_problem {
    my ($pid, $code, $to_contest) = @_;

    my $problem = _prepare_move($pid, $to_contest) or return;
    is_jury_in_contest(contest_id => $problem->{contest_id}) or return msg(1012);

    if (!_get_cpid($to_contest, $pid)) {
        _add_problem_to_contest($to_contest, $pid, $code) or return;
    }
    $dbh->do(_u $sql->update(problems => { contest_id => $to_contest }, { id => $pid }));
    $dbh->commit;
    msg(1021, $problem->{title});
    1;
}

sub set_problem_import_diff {
    my ($pid, $sha) = @_;
    $t->param(problem_import_diff => {
        sha => $sha,
        abbreviated_sha => substr($sha, 0, 8),
        href_commit => url_f('problem_history_commit', pid => $pid, h => $sha),
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

    my CATS::Problem::Storage $p = CATS::Problem::Storage->new;
    return if CATS::Problem::Storage::get_repo($pid, undef, 1, logger => CATS::Problem::Storage->new)->is_remote;

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

sub unused_problem_code {
    my ($self) = @_;
    my %used_codes;
    @used_codes{@{$contest->used_problem_codes}} = undef;
    for ('A'..'Z', '1'..'9') {
        return $_ if !exists $used_codes{$_};
    }
    undef;
}

sub problems_add {
    my ($source_name, $is_remote) = @_;
    my $problem_code;
    if (!$contest->is_practice) {
        ($problem_code) = unused_problem_code or return msg(1017);
    }

    my CATS::Problem::Storage $p = CATS::Problem::Storage->new;
    my ($error, $result_sha, $problem) = $is_remote
              ? $p->load(CATS::Problem::Source::Git->new($source_name, $p), $cid, new_id, 0, $source_name)
              : $p->load(CATS::Problem::Source::Zip->new($source_name, $p), $cid, new_id, 0, undef);
    $t->param(problem_import_log => $p->encoded_import_log());
    $error ||= !_add_problem_to_contest($cid, $problem->{id}, $problem_code);

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
