package CATS::UI::RequestParams;

use strict;
use warnings;

use JSON::XS;

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($is_root $t $uid);
use CATS::JudgeDB;
use CATS::Messages qw(msg);
use CATS::Output qw(init_template url_f);
use CATS::RankTable::Cache;
use CATS::Request;
use CATS::ReqDetails qw(
    get_sources_info
    sources_info_param
    source_links);
use CATS::Verdicts;

sub maybe_reinstall {
    my ($p, $si) = @_;
    $p->{reinstall} && $si->{can_reinstall} or return;
    # Advance problem modification date to mark judges' cache stale.
    $dbh->do(q~
        UPDATE problems SET upload_date = CURRENT_TIMESTAMP WHERE id = ?~, undef,
        $si->{problem_id});
}

sub maybe_status_ok {
    my ($p, $si) = @_;
    $p->{status_ok} or return;
    $dbh->do(q~
        UPDATE contest_problems SET status = ?
        WHERE contest_id = ? AND problem_id = ? AND status <> ?~, undef,
        $cats::problem_st_ready, $si->{contest_id}, $si->{problem_id}, $cats::problem_st_ready);
}

sub _try_set_user {
    my ($p, $si) = @_;
    $p->{set_user} && $p->{new_login} or return;
    my ($new_account_id, $new_name) = $dbh->selectrow_array(q~
        SELECT A.id, A.team_name FROM accounts A
        INNER JOIN contest_accounts CA ON CA.account_id = A.id
        WHERE CA.contest_id = ? AND A.login = ?~, undef,
        $si->{contest_id}, $p->{new_login})
        or return msg(1139, $p->{new_login});
    $dbh->do(q~
        UPDATE reqs SET account_id = ? WHERE id = ?~, undef,
        $new_account_id, $si->{req_id});
    $dbh->commit;
}

my $settable_verdicts = [ qw(NP AW OK WA PE TL ML WL RE CE SV IS IL MR LI BA) ];

sub request_params_frame {
    my ($p) = @_;

    init_template($p, 'request_params.html.tt');
    $p->{rid} or return;

    my $si = get_sources_info($p, request_id => $p->{rid}) or return;
    $si->{is_jury} or return;

    my @limits_fields = (@cats::limits_fields, 'job_split_strategy');

    my $limits = { map { $_ => $p->{$_} || undef } grep $p->{"set_$_"}, @limits_fields };
    my $need_clear_limits = 0 == grep $p->{"set_$_"}, @limits_fields;

    if ($p->{single_judge}) {
        $limits->{job_split_strategy} = encode_json({method => $cats::split_none});
        $need_clear_limits = 0;
    }

    if (!$need_clear_limits) {
        my $filtered_limits = CATS::Request::filter_valid_limits($limits);
        my @invalid_limits_keys = grep !exists $filtered_limits->{$_}, keys %$limits;
        if (@invalid_limits_keys) {
            $need_clear_limits = 0;
            msg(1144);
        }
    }

    $si->{need_status_ok} = $si->{status} >= $cats::problem_st_suspended && !$si->{submitter_is_jury};
    my $params = {
        state => $cats::st_not_processed,
        # Insert NULL into database to be replaced with contest-default testset.
        testsets => $p->{testsets} || undef,
        judge_id => ($p->{set_judge} && $p->{judge} ? $p->{judge} : undef),
        points => undef, failed_test => 0,
    };

    if ($p->{retest}) {
        if ($need_clear_limits) {
            $params->{limits_id} = undef;
        } else {
            $params->{limits_id} = CATS::Request::set_limits($si->{limits_id}, $limits);
        }
        CATS::Request::enforce_state($si->{req_id}, $params);
        CATS::Job::create_or_replace($cats::job_type_submission, { req_id => $si->{req_id} });

        CATS::Request::delete_limits($si->{limits_id}) if $need_clear_limits && $si->{limits_id};
        maybe_reinstall($p, $si);
        maybe_status_ok($p, $si);
        CATS::RankTable::Cache::remove($si->{contest_id}) unless $si->{is_hidden};
        $dbh->commit;
        $si = get_sources_info($p, request_id => $si->{req_id});
    }
    if ($p->{clone}) {
        if (!$need_clear_limits) {
            if ($si->{limits_id}) {
                $params->{limits_id} = CATS::Request::clone_limits($si->{limits_id}, $limits);
            } else {
                $params->{limits_id} = CATS::Request::set_limits(undef, $limits);
            }
        }
        my $group_req_id = CATS::Request::clone($si->{req_id}, $si->{contest_id}, $uid, $params);
        maybe_reinstall($p, $si);
        maybe_status_ok($p, $si);
        $dbh->commit;
        return $group_req_id ? $p->redirect(url_f 'request_params', rid => $group_req_id) : undef;
    }
    my $can_delete = !$si->{is_official} || $is_root || ($si->{account_id} // 0) == $uid;
    $t->param(can_delete => $can_delete);
    if ($p->{delete_request} && $can_delete) {
        CATS::Request::delete($si->{req_id});
        CATS::RankTable::Cache::remove($si->{contest_id});
        $dbh->commit;
        msg(1056, $si->{req_id});
        return;
    }

    if ($p->{set_tag}) {
        $dbh->do(q~
            UPDATE reqs SET tag = ? WHERE id = ?~, undef,
            $p->{tag}, $si->{req_id});
        $dbh->commit;
        $si->{tag} = $p->{tag};
    }

    $t->param(href_find_users => url_f('api_find_users', in_contest => $si->{contest_id}));

    # Reload problem after the successful change.
    $si = get_sources_info($p, request_id => $si->{req_id})
        if try_set_state($p, $si) || _try_set_user($p, $si);

    my $tests = $dbh->selectcol_arrayref(q~
        SELECT rank FROM tests WHERE problem_id = ? ORDER BY rank~, undef,
        $si->{problem_id});
    $t->param(tests => [ map { test_index => $_ }, @$tests ]);

    source_links($p, $si);
    sources_info_param([ $si ]);
    $t->param(settable_verdicts => $settable_verdicts);

    if ($is_root) {
        my $judge_de_bitmap =
            CATS::DB::select_row('judge_de_bitmap_cache', '*', { judge_id => $si->{judge_id} }) ||
            { version => 0, de_bits1 => 0, de_bits2 => 0 };
        my ($req_cond, @req_params) =
            CATS::JudgeDB::dev_envs_condition($judge_de_bitmap, $judge_de_bitmap->{version}, 'RDEBC');
        my ($pr_cond, @pr_params) =
            CATS::JudgeDB::dev_envs_condition($judge_de_bitmap, $judge_de_bitmap->{version}, 'PDEBC');

        my $rf = join ', ', map "RDEBC.de_bits$_ AS request_de_bits$_", 1 .. $cats::de_req_bitfields_count;
        my $pf = join ', ', map "PDEBC.de_bits$_ AS problem_de_bits$_", 1 .. $cats::de_req_bitfields_count;

        my $cache = $dbh->selectrow_hashref(qq~
            SELECT
                RDEBC.version AS request_version, $rf,
                PDEBC.version AS problem_version, $pf,
                (CASE WHEN $req_cond AND $pr_cond THEN 1 ELSE 0 END) AS is_supported
            FROM reqs R
                INNER JOIN problems P ON P.id = R.problem_id
                LEFT JOIN req_de_bitmap_cache RDEBC ON RDEBC.req_id = R.id
                LEFT JOIN problem_de_bitmap_cache PDEBC ON PDEBC.problem_id = P.id
            WHERE
                R.id = ?~, undef,
            @req_params, @pr_params, $si->{req_id});
        $t->param(de_cache => $cache);
    }
}

sub try_set_state {
    my ($p, $si) = @_;
    $p->{set_state} && $p->{state} or return;
    grep $_ eq $p->{state}, @$settable_verdicts or return;
    my $state = $CATS::Verdicts::name_to_state->{$p->{state}};

    CATS::Job::cancel_all($si->{req_id});
    CATS::Request::enforce_state($p->{rid}, {
        failed_test => $p->{failed_test}, state => $state, points => $p->{points}
    });
    $dbh->commit;
    CATS::RankTable::Cache::remove($si->{contest_id}) unless $si->{is_hidden};
    msg(1055);
    1;
}

1;
