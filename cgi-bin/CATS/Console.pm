use strict;
use warnings;

package CATS::Console::Part;

use CATS::DB;
use CATS::Globals qw($cid $is_root);

sub new {
    my ($class, $sql, $globals) = @_;
    my $self = {
        sql => $sql,
        cond => '',
        params => [],
        %$globals,
    };
    bless $self, $class;
}

sub add {
    my ($self, $cond, @params) = @_;
    $self->{cond} .= ' AND ' if $self->{cond};
    $self->{cond} .= $cond;
    push @{$self->{params}}, @params;
    $self;
}

sub days {
    my ($self, $field) = @_;
    $self->add("CURRENT_TIMESTAMP - $field < ?", $self->{day_count}) if defined $self->{day_count};
    $self;
}

sub search {
    my ($self) = @_;
    my $w = $self->{lv}->where;
    %$w or return $self;
    my ($search_where, @search_params) = $sql->where($w);
    $search_where =~ s/^\s*WHERE\s*//;
    $self->add($search_where, @search_params);
    $self;
}

sub contest {
    my ($self, $cond) = @_;
    return $self->add($cond, $cid) if !$is_root;
    my $scid = $self->{search_cid};
    ref $scid eq 'ARRAY' && @$scid  or return $self;
    if (@$scid > 1) {
        my $m = join ', ', ('?') x @$scid;
        $cond =~ s/= \?/IN ($m)/;
    }
    $self->add($cond, @$scid);
}

sub sql {
    my ($self) = @_;
    my $where = $self->{cond} ? " WHERE $self->{cond}" : '';
    my $q = $is_root && !defined $self->{day_count} ?
        # Prevent server overload by limiting each subquery separately.
        'SELECT * FROM (SELECT %s%s ORDER BY 2 DESC ROWS %d)' :
        'SELECT %s%s';
    sprintf($q, $self->{sql}, $where, CATS::Globals::max_fetch_row_count);
}

package CATS::Console;

use CATS::DB;
use CATS::Globals qw($is_jury $t $uid $user);
use CATS::Messages qw(res_str);
use CATS::Time;
use CATS::Utils qw(escape_xml);
use CATS::Verdicts;

our @contest_date_types = qw(start freeze finish);

sub _time_interval_days {
    my ($s) = @_;
    my ($v, $u) = @$s{qw(i_value i_unit)};
    my @text = split /\|/, res_str(1121);
    my $units = [
        { value => 'hours', k => 1 / 24 },
        { value => 'days', k => 1 },
        { value => 'months', k => 30 },
    ];
    map { $units->[$_]->{text} = $text[$_] } 0..$#$units;

    my $selected_unit = $units->[0];
    for (@$units) {
        if ($_->{value} eq $u) {
            $selected_unit = $_;
            last;
        }
    }
    $selected_unit->{selected} = 1;

    $t->param(
        i_values => [
            map { { value => $_, text => ($_ > 0 ? $_ : res_str(558)) } }
                (1..5, 10, 20, -1)
        ],
        i_units => $units
    );

    return $v > 0 ? $v * $selected_unit->{k} : undef;
}

sub build_query {
    my ($s, $lv, $user_filter) = @_;

    my $dummy_account_block = q~
        CAST(NULL AS INTEGER) AS team_id,
        CAST(NULL AS VARCHAR(200)) AS team_name,
        CAST(NULL AS VARCHAR(30)) AS country,
        CAST(NULL AS VARCHAR(100)) AS last_ip,
        CAST(NULL AS INTEGER) AS caid
    ~;
    my $dummy_req_block = q~
        CAST(NULL AS INTEGER) AS request_state,
        CAST(NULL AS INTEGER) AS failed_test,
        CAST(NULL AS INTEGER) AS problem_id,
        CAST(NULL AS INTEGER) AS elements_count,
        CAST(NULL AS VARCHAR(200)) AS problem_title
    ~;
    my $no_de = 'CAST(NULL AS VARCHAR(200)) AS de';
    my $city_sql = $is_jury ?
        q~ || (CASE WHEN A.city IS NULL OR A.city = '' THEN '' ELSE ' (' || A.city || ')' END)~ : '';
    my %parts_sql = (
        run => qq~
            1 AS rtype,
            R.submit_time AS rank,
            R.submit_time,
            R.id AS id,
            R.state AS request_state,
            R.failed_test AS failed_test,
            R.problem_id AS problem_id,
            R.elements_count,
            P.title AS problem_title,
            (SELECT s.de_id FROM sources s WHERE s.req_id = R.id) AS de,
            R.points AS clarified,
            NULL AS question,
            NULL AS answer,
            CAST(R.tag AS BLOB SUB_TYPE TEXT) AS jury_message,
            A.id AS team_id,
            A.team_name$city_sql AS team_name,
            A.country AS country,
            COALESCE(E.ip, A.last_ip) AS last_ip,
            CA.id AS caid,
            R.contest_id
            FROM reqs R
            INNER JOIN problems P ON R.problem_id = P.id
            INNER JOIN accounts A ON R.account_id = A.id
            INNER JOIN contests C ON R.contest_id = C.id
            LEFT JOIN contest_accounts CA ON CA.account_id = A.id AND CA.contest_id = R.contest_id
            LEFT JOIN events E ON E.id = R.id
        ~,
        question => qq~
            2 AS rtype,
            Q.submit_time AS rank,
            Q.submit_time,
            Q.id AS id,
            $dummy_req_block,
            $no_de,
            Q.clarified AS clarified,
            Q.question AS question,
            Q.answer AS answer,
            NULL AS jury_message,
            A.id AS team_id,
            A.team_name AS team_name,
            A.country AS country,
            A.last_ip AS last_ip,
            CA.id AS caid,
            CA.contest_id
            FROM questions Q
            INNER JOIN contest_accounts CA ON Q.account_id = CA.id
            INNER JOIN accounts A ON CA.account_id = A.id
            INNER JOIN contests C ON C.id = CA.contest_id
        ~,
        message => qq~
            3 AS rtype,
            E.ts AS rank,
            E.ts AS submit_time,
            M.id AS id,
            $dummy_req_block,
            $no_de,
            CAST(NULL AS INTEGER) AS clarified,
            NULL AS question,
            NULL AS answer,
            M.text AS jury_message,
            A.id AS team_id,
            A.team_name AS team_name,
            A.country AS country,
            A.last_ip AS last_ip,
            CA.id AS caid,
            M.contest_id
            FROM messages M
            INNER JOIN events E ON E.id = M.id
            INNER JOIN accounts A ON E.account_id = A.id
            LEFT JOIN contests C ON C.id = M.contest_id
            LEFT JOIN contest_accounts CA ON M.contest_id = CA.contest_id AND E.account_id = CA.account_id
        ~,
        broadcast => qq~
            4 AS rtype,
            E.ts AS rank,
            E.ts AS submit_time,
            M.id AS id,
            $dummy_req_block,
            $no_de,
            CAST(NULL AS INTEGER) AS clarified,
            NULL AS question,
            NULL AS answer,
            M.text AS jury_message,
            $dummy_account_block,
            M.contest_id
            FROM messages M
            INNER JOIN events E ON E.id = M.id
            LEFT JOIN contests C ON C.id = M.contest_id
        ~,
        (map { +"contest_$contest_date_types[$_]" => qq~
            5 AS rtype,
            C.$contest_date_types[$_]_date AS rank,
            C.$contest_date_types[$_]_date AS submit_time,
            C.id AS id,
            C.is_official AS request_state,
            $_ AS failed_test,
            CAST(NULL AS INTEGER) AS problem_id,
            CAST(NULL AS INTEGER) AS elements_count,
            C.title AS problem_title,
            $no_de,
            CAST(NULL AS INTEGER) AS clarified,
            NULL AS question,
            NULL AS answer,
            NULL AS jury_message,
            $dummy_account_block,
            C.id AS contest_id
            FROM contests C
        ~ } 0 .. $#contest_date_types),
    );

    my $globals = {
        day_count => _time_interval_days($s),
        search_cid => $lv->qb->extract_search_values('contest_id'),
        lv => $lv,
    };
    my %parts = map { $_ => CATS::Console::Part->new($parts_sql{$_}, $globals) } keys %parts_sql;

    my @selected_parts;
    my $select_part = sub { push @selected_parts, $_[0]; $parts{$_[0]}; };

    if (@$user_filter) {
        my $events_filter = '(' . join(' OR ', map 'A.id = ?', @$user_filter) . ')';
        $parts{$_}->add($events_filter, @$user_filter) for qw(run question message);
    }

    if (!$is_jury || $s->{show_results}) {
        my $run = $select_part->('run')->days('R.submit_time')->contest('C.id = ?')->search;
        if (!$is_jury) {
            $run->add('CA.is_hidden = 0');
            my $submit_time =
                '(R.submit_time BETWEEN C.start_date AND C.freeze_date OR CURRENT_TIMESTAMP > C.defreeze_date)';
            $run->add($uid ? ("(R.account_id = ? OR $submit_time)", $uid) : ($submit_time));
        }
    }

    if (!$is_jury || $s->{show_messages}) {
        if ($uid) {
            my $question = $select_part->('question')->days('Q.submit_time')->contest('CA.contest_id = ?');
            my $message = $select_part->('message')->days('E.ts')
                ->contest('(M.contest_id IS NULL OR M.contest_id = ?)');

            my $msg_subset = { account_id => 1, team_name => 1, city => 1, contest_id => 1 };
            if ($lv->qb->searches_subset_of($msg_subset)) {
                $question->search;
                $message->search;
            }
            if (!$is_jury) {
                $question->add('A.id = ?', $uid);
                $message->add('E.account_id = ?', $uid);
            }
        }

        $select_part->('broadcast')->days('E.ts')->add('M.broadcast = 1')
            ->contest('(M.contest_id IS NULL OR M.contest_id = ?)');
    }

    if (!$is_jury || $s->{show_contests}) {
        for (@contest_date_types) {
            $select_part->("contest_$_")->days("C.${_}_date")->contest('C.id = ?')
                ->add("C.${_}_date < CURRENT_TIMESTAMP");
        }
        # Display freeze if distinct from start and finish.
        $parts{contest_freeze}->add('C.start_date < C.freeze_date AND C.freeze_date < C.finish_date');
    }

    @selected_parts or return;
    my $sql = join ' UNION ', map $parts{$_}->sql, @selected_parts;
    #warn $sql;
    my $sth = $dbh->prepare("$sql ORDER BY 2 DESC");
    #warn join ',', map @{$console_params{$_}}, @selected_parts;
    $sth->execute(map @{$parts{$_}->{params}}, @selected_parts);
    $sth;
}

sub select_all_reqs {
    my ($contest_id, $params) = @_;
    my $site_sql = $params->{site_id} ? ' AND CA.site_id = ?' : '';
    $dbh->selectall_arrayref(qq~
        SELECT
            R.id AS id, R.submit_time, R.state, R.failed_test, R.points,
            R.submit_time - $CATS::Time::contest_start_offset_sql AS time_since_start,
            CP.code, P.title AS problem_title,
            A.id AS team_id, A.team_name,
            COALESCE(E.ip, A.last_ip) AS last_ip,
            CA.is_remote, CA.is_ooc, S.name AS site_name,
            (SELECT LIST(code) FROM default_de D INNER JOIN sources S ON S.de_id = D.id
                WHERE S.req_id = R.id) AS de_code
        FROM
            reqs R
            INNER JOIN problems P ON R.problem_id = P.id
            INNER JOIN contest_accounts CA ON CA.contest_id = R.contest_id AND CA.account_id = R.account_id
            INNER JOIN contests C ON R.contest_id = C.id
            INNER JOIN contest_problems CP ON R.contest_id = CP.contest_id AND CP.problem_id = R.problem_id
            INNER JOIN accounts A ON CA.account_id = A.id
            LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
            LEFT JOIN sites S ON S.id = CA.site_id
            LEFT JOIN events E ON E.id = R.id
        WHERE
            R.contest_id = ? AND CA.is_hidden = 0 AND CA.is_virtual = 0 AND R.submit_time > C.start_date
            $site_sql
        ORDER BY R.submit_time ASC~, { Slice => {} },
        $contest_id, ($params->{site_id} || ()));
}

sub export {
    my ($contest_id, $params) = @_;
    # Legacy field, new consumers should use short_state.
    my %state_to_display = (
        $cats::st_wrong_answer => 'wrong_answer',
        $cats::st_presentation_error => 'presentation_error',
        $cats::st_time_limit_exceeded => 'time_limit_exceeded',
        $cats::st_memory_limit_exceeded => 'memory_limit_exceeded',
        $cats::st_memory_limit_exceeded => 'write_limit_exceeded',
        $cats::st_runtime_error => 'runtime_error',
        $cats::st_compilation_error => 'compilation_error',
        $cats::st_idleness_limit_exceeded => 'idleness_limit_exceeded',
        $cats::st_manually_rejected => 'manually_rejected',
        $cats::st_not_processed => 'not_processed',
        $cats::st_unhandled_error => 'unhandled_error',
        $cats::st_install_processing => 'install_processing',
        $cats::st_testing => 'testing',
        $cats::st_awaiting_verification => 'awaiting_verification',
        $cats::st_accepted => 'accepted',
        $cats::st_security_violation => 'security_violation',
        $cats::st_ignore_submit => 'ignore_submit',
    );
    my $reqs = select_all_reqs($contest_id, $params);
    for my $req (@$reqs) {
        $req->{submit_time} =~ s/\s+$//;
        $req->{short_state} = $CATS::Verdicts::state_to_name->{$req->{state}};
        $req->{state} = $state_to_display{$req->{state}};
        $req->{s} = join '', map "<$_>" . escape_xml($req->{$_}) . "</$_>",
            sort grep defined $req->{$_}, keys %$req;
    }
    $reqs;
}

1;
