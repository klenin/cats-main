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

sub job_details_frame {
    my ($p) = @_;
    init_template($p, 'run_log.html.tt');
    my $lv = CATS::ListView->new(name => 'job_details');

    CATS::Request::delete_logs({ id => $p->{jid} }) if $p->{delete_log};

    $t->param(
        logs => CATS::ReqDetails::get_log_dump({ id => $p->{jid} })
    );
}

sub jobs_frame {
    my ($p) = @_;
    $is_jury or return;

    init_template($p, 'jobs.html.tt');
    my $lv = CATS::ListView->new(name => 'jobs');

    $lv->define_columns(url_f('jobs'), 0, 0, [
        { caption => res_str(642), order_by => 'type', width => '5%' },
        { caption => res_str(619), order_by => 'id', width => '5%' },
        { caption => res_str(622), order_by => 'state', width => '5%' },
        { caption => res_str(632), order_by => 'start_time', width => '10%' },
        { caption => res_str(673), order_by => 'judge_name', width => '10%', col => 'Jn' },
        { caption => res_str(602), order_by => 'problem_title', width => '15%', col => 'Pr' },
        { caption => res_str(603), order_by => 'contest_title', width => '15%', col => 'Ct' },
        { caption => res_str(608), order_by => 'team_name', width => '15%', col => 'Ac' },
    ]);
    $lv->define_db_searches([ qw(
        id type state start_time judge_id judge_name
        problem_id problem_title J1.contest_id contest_title account_id team_name req_id
        in_queue
    ) ]);

    my $job_name_to_type = {
        submission => $cats::job_type_submission,
        snippets => $cats::job_type_generate_snippets,
        install => $cats::job_type_initialize_problem,
    };
    my $job_name_to_state = {
        waiting => $cats::job_st_waiting,
        running => $cats::job_st_in_progress,
        finished => $cats::job_st_finished,
    };
    my $judges = $dbh->selectall_arrayref(q~
        SELECT nick, id FROM judges WHERE pin_mode > ?~, undef,
        $cats::judge_pin_locked);
    $lv->define_enums({
        type => $job_name_to_type,
        state => $job_name_to_state,
        contest_id => { this => $cid },
        judge_id => { map @$_, @$judges },
    });
    $t->param(
        job_type_to_name => { map { $job_name_to_type->{$_} => $_ } keys %$job_name_to_type },
        job_state_to_name => { map { $job_name_to_state->{$_} => $_ } keys %$job_name_to_state },
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
        [ qw(J.id J.type J.state J.start_time J.req_id J.judge_id),
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
            href_details => url_f(
                $row->{type} == $cats::job_type_submission ? ('run_details', rid => $row->{req_id}) :
                ('job_details', jid => $row->{id})
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
