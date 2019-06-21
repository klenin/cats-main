package CATS::UI::Jobs;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($cid $is_jury $is_root $sid $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::Utils qw(url_function);
use CATS::Request;
use CATS::ReqDetails;
use CATS::Time;

sub job_details_frame {
    my ($p) = @_;
    init_template($p, 'run_log.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'job_details');

    CATS::Request::delete_logs({ id => $p->{jid} }) if $p->{delete_log};
    CATS::Request::delete_jobs({ id => $p->{jid} }) if $p->{delete_jobs};

    $t->param(
        logs => CATS::ReqDetails::get_log_dump({ id => $p->{jid} }),
        job_enums => $CATS::Globals::jobs,
    );
}

sub jobs_frame {
    my ($p) = @_;
    $is_jury or return;

    init_template($p, 'jobs.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'jobs');

    $lv->define_columns(url_f('jobs'), 0, 0, [
        { caption => res_str(642), order_by => 'type', width => '5%' },
        { caption => res_str(619), order_by => 'id', width => '5%' },
        { caption => res_str(622), order_by => 'state', width => '5%' },
        { caption => 'create_time', order_by => 'create_time', width => '5%', col => 'Tc' },
        { caption => 'start_time' , order_by => 'start_time' , width => '5%', col => 'Ts' },
        { caption => 'finish_time', order_by => 'finish_time', width => '5%', col => 'Tf' },
        { caption => 'time_len'   , order_by => 'time_len'   , width => '5%', col => 'Tt' },
        { caption => res_str(673), order_by => 'judge_name', width => '10%', col => 'Jn' },
        { caption => res_str(602), order_by => 'problem_title', width => '15%', col => 'Pr' },
        { caption => res_str(603), order_by => 'contest_title', width => '15%', col => 'Ct' },
        { caption => res_str(608), order_by => 'team_name', width => '15%', col => 'Ac' },
    ]);
    $lv->define_db_searches([ qw(
        id type state create_time start_time finish_time time_len judge_id judge_name
        J1.contest_id contest_title account_id team_name req_id
        in_queue
    ) ]);
    $lv->define_db_searches({
        problem_title => 'P.title',
        problem_id => 'P.id',
    });

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
    );

    my $maybe_field = sub {
        ($lv->visible_cols->{$_[0]} ? "COALESCE(J.$_[1], R.$_[1])" : 'NULL') . " AS $_[1]"
    };
    my $where = $lv->where;
    $is_root or $where->{'J1.contest_id'} = $cid;

    my ($q) = $sql->select(
        'jobs J LEFT JOIN jobs_queue JQ ON JQ.id = J.id' .
        ($lv->visible_cols->{Jn} ? ' LEFT JOIN judges JD ON J.judge_id = JD.id' : '') .
        ($lv->visible_cols->{Pr} || $lv->visible_cols->{Ct} || $lv->visible_cols->{Ac} ?
            ' LEFT JOIN reqs R ON J.req_id = R.id' : ''),
        [ qw(J.id J.type J.state J.create_time J.start_time J.finish_time J.req_id J.judge_id),
          'CAST(J.finish_time - J.start_time AS DOUBLE PRECISION) AS time_len',
          'CASE WHEN JQ.id IS NULL THEN 0 ELSE 1 END AS in_queue',
          ($lv->visible_cols->{Jn} ?  'JD.nick' : 'NULL') . ' AS judge_name',
          $maybe_field->('Pr', 'problem_id'),
          $maybe_field->('Ct', 'contest_id'),
          $maybe_field->('Ac', 'account_id'),
        ]
    );
    my ($q1, @bind) = $sql->select("($q) J1 " .
        ($lv->visible_cols->{Pr} ? q~
            LEFT JOIN problems P ON P.id = J1.problem_id
            LEFT JOIN contest_problems CP ON
                CP.problem_id = J1.problem_id AND CP.contest_id = J1.contest_id ~ : '') .
        ($lv->visible_cols->{Ct} ? q~LEFT JOIN contests C ON C.id = J1.contest_id ~ : '') .
        ($lv->visible_cols->{Ac} ? q~LEFT JOIN accounts A ON A.id = J1.account_id ~ : ''),
        [ 'J1.*',
            ($lv->visible_cols->{Pr} ? 'P.title' : 'NULL') . ' AS problem_title',
            ($lv->visible_cols->{Pr} ? 'CP.id' : 'NULL') . ' AS cpid',
            ($lv->visible_cols->{Ct} ? 'C.title' : 'NULL') . ' AS contest_title',
            ($lv->visible_cols->{Ac} ? 'A.team_name' : 'NULL') . ' AS team_name',
        ], $where
    );
    my $c = $dbh->prepare($q1 . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            time_len_fmt => CATS::Time::format_diff($row->{time_len}, seconds => 1),
            href_details => (
                (grep $row->{type} == $_, $cats::job_type_submission, $cats::job_type_submission_part) ?
                url_f('run_log', rid => $row->{req_id}) . "#job$row->{id}" :
                url_f('job_details', jid => $row->{id})
            ),
            href_problem_text => url_function('problem_text',
                pid => $row->{problem}, cpid => $row->{cpid}, sid => $sid,
                uid => $row->{account_id}),
            href_contest => url_function('problems', cid => $row->{contest_id}, sid => $sid),
            href_user => url_f('user_stats', uid => $row->{account_id}),
            # href_delete => url_f('jobs', 'delete' => $row->{id}),
        );
    };
    $lv->attach(url_f('jobs'), $fetch_record, $c);
}

1;
