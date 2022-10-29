package CATS::UI::Jobs;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($cid $is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f url_f_cid);
use CATS::ReqDetails;
use CATS::Request;
use CATS::Time;

sub job_details_frame {
    my ($p) = @_;
    $is_jury && $p->{jid} or return;
    init_template($p, 'run_log.html.tt');

    my ($job_id, $state, $job_contest) = $dbh->selectrow_array(q~
        SELECT id, state, contest_id FROM jobs WHERE id = ?~, undef,
        $p->{jid});
    $job_id or return;
    ($job_contest // 0) == $cid or $is_root or return;

    CATS::Request::delete_logs({ id => $job_id }) if $p->{delete_log};
    CATS::Request::delete_jobs({ id => $job_id }) if $p->{delete_jobs};
    if ($p->{restart_job} && $state != $cats::job_st_waiting) {
        my $updated = ($dbh->do(q~
            UPDATE jobs SET state = ?, finish_time = NULL
            WHERE id = ? AND state <> ?~, undef,
            $cats::job_st_waiting, $job_id, $cats::job_st_waiting) // 0) > 0;
        if ($updated) {
            $dbh->do(q~
                INSERT INTO jobs_queue (id) VALUES (?)~, undef,
                $p->{jid});
            $dbh->commit;
        }
        msg(1241, $updated);
    }

    $t->param(
        logs => CATS::ReqDetails::get_log_dump({ id => $p->{jid} }),
        job_enums => $CATS::Globals::jobs,
        restart_job => $state != $cats::job_st_waiting,
    );
}

sub jobs_frame {
    my ($p) = @_;
    $is_jury or return;

    init_template($p, 'jobs');
    my $lv = CATS::ListView->new(web => $p, name => 'jobs', url => url_f('jobs'));

    $lv->default_sort(0)->define_columns([
        { caption => res_str(642), order_by => 'type', width => '5%' },
        { caption => res_str(619), order_by => 'J.id', width => '5%' },
        { caption => res_str(622), order_by => 'state', width => '5%' },
        { caption => 'create_time', order_by => 'create_time', width => '5%', col => 'Tc' },
        { caption => 'start_time' , order_by => 'start_time' , width => '5%', col => 'Ts' },
        { caption => 'finish_time', order_by => 'finish_time', width => '5%', col => 'Tf' },
        { caption => 'time_len'   , order_by => 'time_len'   , width => '5%', col => 'Tt' },
        { caption => res_str(673), order_by => 'judge_name', width => '10%', col => 'Jn' },
        { caption => res_str(602), order_by => 'problem_title', width => '15%', col => 'Pr' },
        { caption => res_str(603), order_by => 'contest_title', width => '15%', col => 'Ct' },
        { caption => res_str(608), order_by => 'team_name', width => '15%', col => 'Ac' },
        { caption => res_str(813), order_by => 'parent_id', width => '5%', col => 'Pi' },
        { caption => res_str(684), order_by => 'log_size', width => '5%', col => 'Ls' },
    ]);
    $lv->define_db_searches([ qw(
        J.id type state create_time start_time finish_time judge_id judge_name
        J.problem_id J.contest_id contest_title J.account_id team_name J.parent_id
    ) ]);

    my $fields_sql = {
        in_queue => 'CASE WHEN JQ.id IS NULL THEN 0 ELSE 1 END',
        log_size => '(SELECT SUM(OCTET_LENGTH(dump)) FROM logs L WHERE L.job_id = J.id)',
        time_len => 'CAST(J.finish_time - J.start_time AS DOUBLE PRECISION)',
    };
    $lv->define_db_searches({
        problem_title => 'P.title',
        req_id => q~
            COALESCE(J.req_id, (SELECT PJ.req_id FROM jobs PJ WHERE PJ.id = J.parent_id))~,
        parent_or_id => 'COALESCE(J.parent_id, J.id)',
        %$fields_sql,
    });
    $lv->default_searches([ qw(problem_title contest_title team_name) ]);

    my $judges = $dbh->selectall_arrayref(q~
        SELECT nick, id FROM judges WHERE pin_mode > ?~, undef,
        $cats::judge_pin_locked);

    my $jc = $CATS::Globals::jobs;
    $lv->define_enums({
        type => $jc->{name_to_type},
        state => $jc->{name_to_state},
        contest_id => { this => $cid },
        judge_id => { map @$_, @$judges },
    });
    $t->param(
        job_type_to_name => $jc->{type_to_name},
        job_state_to_name => $jc->{state_to_name},
        submenu => [
            { item => res_str(408), href => url_f('jobs', 'search' => 'in_queue=1') },
            ($is_root ? { item => res_str(585), href => url_f('jobs', 'search' => 'contest_id=this') } : ()),
        ],
    );

    my $where = $lv->where;
    $is_root && %$where or $where->{'J.contest_id'} = $cid;
    my $in_queue_val = $lv->qb->extract_search_values('in_queue');
    my $in_queue = @$in_queue_val == 1 && $in_queue_val->[0];
    my $type_val = $lv->qb->extract_search_values('type');
    my $type_noreq = @$type_val &&
        0 == grep $_ != $cats::job_type_update_self && $_ != $cats::job_type_run_command, @$type_val;

    my @job_common_fields =
        qw(id type state create_time start_time finish_time req_id judge_id parent_id);
    my $jobs_reqs_sql = $type_noreq ? '' : sprintf q~
        UNION
        SELECT %s, R.contest_id, R.problem_id, R.account_id
        FROM jobs J2%s INNER JOIN reqs R ON J2.req_id = R.id~,
        (join ', ', map "J2.$_", @job_common_fields),
        $in_queue ? ' INNER JOIN jobs_queue JQ ON JQ.id = J2.id' : '';
    my $jobs_sql = sprintf q~(
        SELECT %s, J1.contest_id, J1.problem_id, J1.account_id
        FROM jobs J1%s WHERE J1.req_id IS NULL
        %s
        ) J
        %s JOIN jobs_queue JQ ON JQ.id = J.id~,
        (join ', ', map "J1.$_", @job_common_fields),
        $in_queue ? ' INNER JOIN jobs_queue JQ ON JQ.id = J1.id' : '',
        $jobs_reqs_sql,
        $in_queue ? 'INNER' : 'LEFT';
    my ($q, @bind) = $sql->select($jobs_sql .
        ($lv->visible_cols->{Jn} ? ' LEFT JOIN judges JD ON J.judge_id = JD.id' : '') .
        ($lv->visible_cols->{Pr} ? q~
            LEFT JOIN problems P ON P.id = J.problem_id
            LEFT JOIN contest_problems CP ON
                CP.problem_id = J.problem_id AND CP.contest_id = J.contest_id ~ : '') .
        ($lv->visible_cols->{Ct} ? q~LEFT JOIN contests C ON C.id = J.contest_id ~ : '') .
        ($lv->visible_cols->{Ac} ? q~LEFT JOIN accounts A ON A.id = J.account_id ~ : ''),
        [
            (map "J.$_", @job_common_fields, qw(problem_id contest_id account_id)),
            "$fields_sql->{time_len} AS time_len",
            "$fields_sql->{in_queue} AS in_queue",
            ($lv->visible_cols->{Jn} ? 'JD.nick' : 'NULL') . ' AS judge_name',
            ($lv->visible_cols->{Pr} ? 'P.title' : 'NULL') . ' AS problem_title',
            ($lv->visible_cols->{Pr} ? 'CP.id' : 'NULL') . ' AS cpid',
            ($lv->visible_cols->{Ct} ? 'C.title' : 'NULL') . ' AS contest_title',
            ($lv->visible_cols->{Ac} ? 'A.team_name' : 'NULL') . ' AS team_name',
            ($lv->visible_cols->{Ls} ? $fields_sql->{log_size} : 'NULL') . ' AS log_size',
        ], $where
    );
    my $sth = $dbh->prepare($q . $lv->order_by);
    $sth->execute(@bind);

    my $href_details = sub {
        my ($row) = @_;
        (grep $row->{type} == $_, $cats::job_type_submission, $cats::job_type_submission_part) ?
            url_f('run_log', rid => $row->{req_id}) . "#job$row->{id}" :
            url_f('job_details', jid => $row->{id});
    };

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            time_len_fmt => CATS::Time::format_diff($row->{time_len}, seconds => 1),
            href_details => $href_details->($row),
            href_problem_text => url_f_cid('problem_text',
                pid => $row->{problem}, cpid => $row->{cpid},
                uid => $row->{account_id}),
            href_contest => url_f_cid('problems', cid => $row->{contest_id}),
            href_user => url_f('user_stats', uid => $row->{account_id}),
            # href_delete => url_f('jobs', 'delete' => $row->{id}),
        );
    };
    $lv->date_fields(qw(create_time start_time finish_time));
    $lv->attach($fetch_record, $sth);
}

1;
