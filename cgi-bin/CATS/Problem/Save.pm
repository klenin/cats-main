package CATS::Problem::Save;

use strict;
use warnings;

use File::Temp;
use Template;

use CATS::Contest;
use CATS::Contest::Participate qw(is_jury_in_contest);
use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($t $cid $uid $contest);
use CATS::Messages qw(msg);
use CATS::Output qw(url_f);
use CATS::Problem::Storage;
use CATS::StaticPages;

sub _get_cpid {
    my ($contest_id, $problem_id) = @_;
    $dbh->selectrow_array(q~
        SELECT id FROM contest_problems WHERE contest_id = ? and problem_id = ?~, undef,
        $contest_id, $problem_id);
}

sub _unused_problem_code {
    my ($c) = @_;
    my %used_codes;
    @used_codes{@{$c->used_problem_codes}} = undef;
    for ('A'..'Z', '1'..'9') {
        return $_ if !exists $used_codes{$_};
    }
    msg(1017);
}

sub _add_problem_to_contest {
    my ($contest_id, $pid, $code) = @_;
    my $target_contest = $contest_id == $cid ? $contest :
        CATS::Contest->new->load($contest_id, [ 'id', 'ctype', CATS::Contest::time_since_sql('start') ]);

    if (!$target_contest->is_practice) {
        $code //= _unused_problem_code($target_contest) or return;
    }
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
    my ($p, $pid) = @_;
    $pid or return msg(1012);
    my $zip = $p->{zip} or return msg(1053);
    $zip->remote_file_name =~ /\.(zip|ZIP)$/ or return msg(1053);

    my ($contest_id, $old_title, $repo) = $dbh->selectrow_array(q~
        SELECT contest_id, title, repo FROM problems WHERE id = ?~, undef,
        $pid);
    # Forbid replacing linked problems. Firstly for robustness,
    # secondly for security -- to avoid checking is_jury($contest_id).
    $contest_id == $cid
        or return msg(1117, $old_title);

    my CATS::Problem::Storage $pr = CATS::Problem::Storage->new;
    return if CATS::Problem::Storage::get_repo(
        $pid, undef, 1, logger => CATS::Problem::Storage->new)->is_remote;

    my $fname = $zip->local_file_name;

    $pr->{old_title} = $old_title unless $p->{allow_rename};
    my ($error, $result_sha) = $pr->load(
        CATS::Problem::Source::Zip->new($fname, $pr), $cid, $pid, 1, $repo, $p->{message}, $p->{is_amend});
    $t->param(problem_import_log => $pr->encoded_import_log());
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
    my ($source_name, %opts) = @_;

    $opts{source} or die;

    my $problem_code;
    if (!$contest->is_practice) {
        $problem_code = _unused_problem_code($contest) or return;
    }

    my CATS::Problem::Storage $ps = CATS::Problem::Storage->new;

    my $source =
        $opts{source} eq 'remote' ?
            CATS::Problem::Source::Git->new($source_name, $ps, $opts{repo_path} || die) :
        $opts{source} eq 'zip' ?
            CATS::Problem::Source::Zip->new($source_name, $ps) :
        $opts{source} eq 'dir' ?
            CATS::Problem::Source::PlainFiles->new(dir => $source_name, logger => $ps) : die;
    my ($error, $result_sha, $problem) =
        $ps->load_problem($source, $cid, new_id, 0, $opts{source} eq 'remote' ? $source_name : undef);

    $t->param(problem_import_log => $ps->encoded_import_log);
    $error ||= !_add_problem_to_contest($cid, $problem->{id}, $problem_code);

    if (!$error) {
        $dbh->commit;
        set_problem_import_diff($problem->{id}, $result_sha);
    } else {
        $dbh->rollback;
        msg(1008);
    }
    $ps->encoded_import_log;
}

sub problems_add_new {
    my ($p) = @_;
    my $zip = $p->{zip} or return msg(1053);
    $zip->remote_file_name =~ /\.(zip|ZIP)$/
        or return msg(1053);
    my $fname = $zip->local_file_name;
    problems_add($fname, source => 'zip');
    unlink $fname;
}

sub problems_add_template {
    my ($template_path, $template_params) = @_;

    my $tmpdir = File::Temp->newdir;
    my $tt = Template->new({
        INCLUDE_PATH => $template_path,
        ENCODING => 'utf8',
    }) or die $Template::ERROR;

    $tt->process('task.xml', $template_params, File::Spec->catdir($tmpdir, 'task.xml'))
        or die $tt->error();
    problems_add($tmpdir->dirname, source => 'dir');
}

sub get_all_des {
    $dbh->selectall_arrayref(q~
        SELECT D.id, D.code, D.description, D.in_contests,
            (SELECT 1 FROM contest_problem_des CPD WHERE CPD.cp_id = ? AND CPD.de_id = D.id) AS allow
        FROM default_de D
        ORDER BY D.code~, { Slice => {} }, $_[0]
    );
}

sub problems_add_new_remote {
    my ($p) = @_;
    $p->{remote_url} or return msg(1091);
    problems_add($p->{remote_url}, source => 'remote', repo_path => $p->{repo_path});
}

sub set_contest_problem_des {
    my ($cpid, $des, $field) = @_;

    my $all_des = get_all_des($cpid);
    my (@delete_des, @insert_des);
    my %indexed_des = map { $_ => 1 } @$des;

    for (@$all_des) {
        my $new = exists $indexed_des{$_->{$field}};
        push @delete_des, $_->{id} if $_->{allow} && !$new;
        push @insert_des, $_->{id} if !$_->{allow} && $new;
        $_->{allow} = $new;
    }

    @delete_des || @insert_des or return $all_des;

    if (@delete_des) {
        $dbh->do(_u $sql->delete('contest_problem_des',
            { cp_id => $cpid, de_id => \@delete_des }));
    }
    if (@insert_des) {
        my $sth = $dbh->prepare(q~
            INSERT INTO contest_problem_des(cp_id, de_id) VALUES (?, ?)~);
        $sth->execute($cpid, $_) for @insert_des;
    }
    $dbh->commit;

    msg(1169, scalar @delete_des, scalar @insert_des);
    $all_des;
}

1;
