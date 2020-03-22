package CATS::Problem::Submit;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB qw(:DEFAULT $db);
use CATS::DevEnv;
use CATS::Globals qw($cid $contest $is_jury $t $uid $user);
use CATS::IP;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(url_f);
use CATS::Request;
use Exporter qw(import);
our @EXPORT_OK = qw(prepare_de prepare_de_list);

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
    my $prev = $dbh->selectcol_arrayref(qq~
        SELECT CAST(CURRENT_TIMESTAMP - R.submit_time AS DOUBLE PRECISION) FROM reqs R
        WHERE R.account_id = ?
        ORDER BY R.submit_time DESC
        $db->{LIMIT} 2~, {},
        $submit_uid);
    my $SECONDS_PER_DAY = 24 * 60 * 60;
    ($prev->[0] || 1) < 3/$SECONDS_PER_DAY ||
    ($prev->[1] || 1) < 20/$SECONDS_PER_DAY;
}

sub user_is_banned {
    my ($problem_id) = @_;
    $uid or return;
    scalar $dbh->selectrow_array(qq~
        SELECT 1 FROM reqs
        WHERE account_id = ? AND contest_id = ? AND problem_id = ? AND state = ? $db->{LIMIT} 1~, undef,
        $uid, $cid, $problem_id, $cats::st_banned);
}

sub _determine_state {
    my ($p) = @_;
    $p->{ignore} || !$is_jury && CATS::IP::is_tor(CATS::IP::get_ip) ?
        $cats::st_ignore_submit : $cats::st_not_processed;
}

sub _get_DEs {
    my ($contest_id, $de_id) = @_;
    my ($has_de_tags) = $dbh->selectrow_array(qq~
        SELECT 1 FROM contest_de_tags CDT WHERE CDT.contest_id = ? $db->{LIMIT} 1~, undef,
        $contest_id);
    my $tag_sql = $has_de_tags ? q~
        SELECT 1 FROM de_de_tags DDT
            INNER JOIN contest_de_tags CDT ON CDT.tag_id = DDT.tag_id
            WHERE DDT.de_id = D.id AND CDT.contest_id = ?~ : q~
        SELECT 1 FROM de_de_tags DDT
            WHERE DDT.de_id = D.id AND DDT.tag_id = ?~;
    my $id_cond = $de_id ? 'AND D.id = ?' : '';
    {
        des => $dbh->selectall_arrayref(qq~
            SELECT D.id, D.id AS de_id, D.code, D.description, D.file_ext,
                D.default_file_ext, D.memory_handicap, D.syntax
            FROM default_de D
            WHERE D.in_contests = 1$id_cond AND EXISTS ($tag_sql)
            ORDER BY code~, { Slice => {} },
            ($de_id ? ($de_id) : ()),
            ($has_de_tags ? $contest_id : $CATS::Globals::default_de_tag)),
        version => CATS::JudgeDB::current_de_version()
    }
}

sub _prepare_de {
    my ($p, $file, $cpid) = @_;
    my $result = {};

    my $did = $p->{de_id} or return msg(1013);
    if ($did eq 'by_extension') {
        my $de = CATS::DevEnv->new(_get_DEs($cid))->by_file_extension($file)
            or return msg(1013);
        $did = $de->{id};
        $result->{de_name} = $de->{description};
    }
    else {
        @{_get_DEs($cid, $did)->{des}} or do {
            $t->param(de_not_allowed => _get_DEs($cid)->{des});
            return;
        };
    }

    my $allowed_des = $dbh->selectall_arrayref(q~
        SELECT CPD.de_id, D.description
        FROM contest_problem_des CPD
        INNER JOIN default_de D ON D.id = CPD.de_id
        WHERE CPD.cp_id = ? ORDER BY D.code~, { Slice => {} },
        $cpid);
    if ($allowed_des && @$allowed_des && 0 == grep $_->{de_id} == $did, @$allowed_des) {
        $result->{de_not_allowed} = $allowed_des;
        return (undef, $result);
    }
    else {
        return ($did, $result);
    }
}

sub prepare_de {
    my ($p, $file, $cpid) = @_;
    my ($did, $r) = _prepare_de(@_);
    $t->param(%$r) if $t;
    $did;
}

sub prepare_de_list {
    my $de_list = CATS::DevEnv->new(_get_DEs($cid));

    my ($allowed_des) = $dbh->selectall_arrayref(_u $sql->select(
        'contest_problems CP LEFT JOIN contest_problem_des CPD ON CP.id = CPD.cp_id',
        'CP.id, CPD.de_id',
        { 'CP.contest_id' => $cid,
            ($is_jury ? () : ('CP.status' => { '<', $cats::problem_st_disabled })) }
    ));

    my $allow_all = 0;
    my %allowed;
    for (@$allowed_des) {
        if($_->{de_id}) {
            $allowed{$_->{de_id}} = 1;
        }
        else {
            $allow_all = 1;
            last;
        }
    }

    my @all_des = $allow_all ? @{$de_list->des} : grep $allowed{$_->{id}}, @{$de_list->des};
    my @de = (
        { de_id => 'by_extension', de_name => res_str(536) },
         map {{ de_id => $_->{id}, de_name => $_->{description}, syntax => $_->{syntax}, code => $_->{code} }} @all_des );
    (de_list => \@de, (@all_des == 1 ? (de_selected => $all_des[0]->{id}) : ()));
}

sub can_submit {
    $is_jury || $user->{is_participant} && ($user->{is_virtual} || !$contest->has_finished_for($user));
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
    length($source_text) < 1000000 or return msg(1214);

    $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM tests T
        WHERE T.problem_id = ? AND T.snippet_name IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM snippets S
            WHERE S.name = T.snippet_name AND S.problem_id = T.problem_id AND
                S.account_id = ? AND S.contest_id = ?)~, undef,
        $pid, $uid // $user->{anonymous_id}, $cid) and return msg(1168);

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

        return msg(1203) if user_is_banned($pid);
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

    my ($did, $result) = _prepare_de($p, $file ? $file->remote_file_name : '', $cpid);
    $t->param(%$result) if $t;
    $did or return (undef, $result);
    # Forbid repeated submissions of the identical code with the same DE.
    my $source_hash = CATS::Utils::source_hash($source_text);
    my ($same_source, $prev_submit_time) = $dbh->selectrow_array(qq~
        SELECT S.req_id, R.submit_time
        FROM sources S INNER JOIN reqs R ON S.req_id = R.id
        WHERE
            R.account_id = ? AND R.problem_id = ? AND
            R.contest_id = ? AND S.hash = ? AND S.de_id = ?
        $db->{LIMIT} 1~, undef,
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
    $result->{href_run_details} = url_f('run_details', rid => $rid);
    $t->param(%$result) if $t;
    my $submit_time = $dbh->selectrow_array(q~
        SELECT submit_time FROM reqs WHERE id = ?~, { Slice => {} },
        $rid);
    $contest_finished ? msg(1087) :
    defined $prev_reqs_count ? msg(1088, $contest->{max_reqs} - $prev_reqs_count - 1) :
    msg(1014, $submit_time);
    ($rid, $result);
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
        SELECT psl.name, psl.src, psl.de_id, psl.fname
        FROM problem_sources ps
        INNER JOIN problem_sources_local psl on ps.id = psl.id
        WHERE ps.problem_id = ? AND (psl.stype = ? OR psl.stype = ?)~);
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

sub _get_upsolver { # TODO
    scalar $dbh->selectrow_array(q~
        SELECT UR.from_id FROM user_relations UR
        WHERE UR.to_id = ? AND UR.rel_type = ? AND EXISTS (
            SELECT CA.account_id FROM contest_accounts CA
            WHERE CA.contest_id = ?)~, undef,
        $uid, $CATS::Globals::relation->{upsolves_for}, $cid);
}

1;
