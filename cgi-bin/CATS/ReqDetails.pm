package CATS::ReqDetails;

use strict;
use warnings;

use CATS::Constants;
use CATS::Contest;
use CATS::Contest::Participate qw(is_jury_in_contest);
use CATS::DB;
use CATS::Globals qw($contest $is_jury $is_root $sid $t $uid);
use CATS::Messages qw(res_str);
use CATS::Output qw(url_f);
use CATS::RankTable;
use CATS::Time;
use CATS::Utils qw(encodings source_encodings url_function);
use CATS::Verdicts;
use CATS::Web qw(encoding_param param url_param);

use Exporter qw(import);
our @EXPORT_OK = qw(
    get_contest_info
    get_contest_tests
    get_log_dump
    get_req_details
    get_sources_info
    get_test_data
    sources_info_param
    source_links
);

sub get_contest_info {
    my ($si, $cache) = @_;

    $_ and return $_ for $cache->{$si->{contest_id}};

    my @show_fields = qw(show_all_tests show_test_resources show_checker_comment show_test_data);
    my $c = $cache->{$si->{contest_id}} = $si->{contest_id} == $contest->{id} ?
        { map { $_ => $contest->{$_} } 'id', 'run_all_tests', @show_fields, 'time_since_defreeze' } :
        CATS::DB::select_row('contests', [
            'id', 'run_all_tests', @show_fields,
            'CAST(CURRENT_TIMESTAMP - defreeze_date AS DOUBLE PRECISION) AS time_since_defreeze' ],
            { id => $si->{contest_id} });

    my $jury_view = $si->{is_jury} && !param('as_user');
    $c->{$_} ||= $jury_view for @show_fields;
    $c->{hide_testset_details} = !$jury_view && $c->{time_since_defreeze} < 0;

    $c;
}

sub get_contest_tests {
    my ($c, $problem_id) = @_;

    my $fields = join ', ',
        ($c->{show_all_tests} ? 't.points' : ()),
        ($c->{show_test_data} ? qq~
            (SELECT ps.fname FROM problem_sources ps WHERE ps.id = t.generator_id) AS gen_name,
            t.param, t.gen_group, t.in_file_size AS input_file_size, t.out_file_size AS answer_file_size,
            SUBSTRING(t.in_file FROM 1 FOR $cats::test_file_cut + 1) AS input,
            SUBSTRING(t.out_file FROM 1 FOR $cats::test_file_cut + 1) AS answer ~ : ());
    my $tests = $c->{tests} = $fields ?
        $dbh->selectall_arrayref(qq~
            SELECT $fields FROM tests t WHERE t.problem_id = ? ORDER BY t.rank~, { Slice => {} },
            $problem_id) : [];
    my $p = $c->{points} = $c->{show_all_tests} ? [ map $_->{points}, @$tests ] : [];
    $c->{show_points} = 0 != grep defined $_ && $_ > 0, @$p;

    $c;
}

sub get_test_data {
    my ($p) = @_;
    $dbh->selectrow_hashref(q~
        SELECT
            T.in_file AS input, T.in_file_size AS input_size,
            T.out_file AS answer, T.out_file_size AS answer_size
        FROM tests T
            INNER JOIN reqs R ON R.problem_id = T.problem_id
        WHERE R.id = ? AND T.rank = ?~, { Slice => {} },
        $p->{rid}, $p->{test_rank});
}

sub get_req_details {
    my ($c, $req, $fields, $accepted_tests) = @_;

    my $sth = $dbh->prepare(qq~
        SELECT $fields FROM req_details WHERE req_id = ? ORDER BY test_rank~);
    $sth->execute($req->{req_id});

    my @result;
    while (my $rd = $sth->fetchrow_hashref) {
        $rd->{is_accepted} = $rd->{result} == $cats::st_accepted ? 1 : 0;
        # When tests are run in random order, and the user looks at the run details
        # while the testing is in progress, he may be able to see 'OK' result
        # for the test ranked above the (unknown at the moment) first failing test.
        # Prevent this by stopping output at the first failed OR not-run-yet test.
        # Note: Tests after the gap in non-continuous testset will be hidden while running.
        last if !$c->{show_all_tests} && $req->{state} < $cats::request_processed &&
            $rd->{is_accepted} && @result && $result[-1]->{test_rank} != $rd->{test_rank} - 1;
        push @result, $rd;
        $accepted_tests->{$rd->{test_rank}} = 1 if $rd->{is_accepted};
        last if !$c->{show_all_tests} && !$rd->{is_accepted};
    }
    @result;
}

sub get_nearby_attempt {
    my ($si, $prevnext, $cmp, $ord, $diff, $extra_params) = @_;
    # TODO: Сheck neighbour's contest to ensure correct access privileges.
    my $na = $dbh->selectrow_hashref(qq~
        SELECT id, submit_time FROM reqs
        WHERE account_id = ? AND problem_id = ? AND id $cmp ?
        ORDER BY id $ord ROWS 1~, { Slice => {} },
        $si->{account_id}, $si->{problem_id}, $si->{req_id}
    ) or return;
    for ($na->{submit_time}) {
        s/\s*$//;
        # If the date is the same with the current run, display only time.
        my ($n_date, $n_time) = /^(\d+\.\d+\.\d+\s+)(.*)$/;
        $si->{"${prevnext}_attempt_time"} = $si->{submit_time} =~ /^$n_date/ ? $n_time : $_;
    }
    my $f = url_param('f') || 'run_log';
    my @p = $extra_params ? @$extra_params : ();
    if ($f eq 'diff_runs') {
        for (1..2) {
            my $r = url_param("r$_") || 0;
            push @p, "r$_" => ($r == $si->{req_id} ? $na->{id} : $r);
        }
    }
    else {
        push @p, (rid => $na->{id});
    }
    $si->{"href_${prevnext}_attempt"} = url_f($f, @p);
    $si->{href_diff_runs} = url_f('diff_runs', r1 => $na->{id}, r2 => $si->{req_id}) if $diff && $uid;
}

sub _get_user_details {
    my ($uid) = @_;
    my $contacts = $dbh->selectall_arrayref(q~
        SELECT C.id, C.handle, CT.name, CT.url
        FROM contacts C INNER JOIN contact_types CT ON CT.id = C.contact_type_id
        WHERE C.account_id = ? AND C.is_actual = 1~, { Slice => {} },
        $uid);
    $_->{href} = sprintf $_->{url}, CATS::Utils::escape_url($_->{handle}) for @$contacts;
    { contacts => $contacts };
}

# Load information about one or several runs.
# Parameters: request_id, may be either scalar or array ref.
sub get_sources_info {
    my %opts = @_;
    my $rid = $opts{request_id} or return;

    my @req_ids = ref $rid eq 'ARRAY' ? @$rid : ($rid);
    @req_ids = map +$_, grep $_ && /^\d+$/, @req_ids or return;

    my @src = $opts{get_source} ? qw(S.src DE.syntax DE.err_regexp) : ();
    my @pc_sql = $opts{partial_checker} ? ( CATS::RankTable::partial_checker_sql() ) : ();

    my @limits = map { my $l = $_; map "$_.$l AS @{[$_]}_$l", qw(lr lcp p) } @cats::limits_fields;

    # Source code can be in arbitary or broken encoding, we need to decode it explicitly.
    $dbh->{ib_enable_utf8} = 0;

    my $req_tree = CATS::JudgeDB::get_req_tree(\@req_ids, {
        fields => [
            'R.id AS req_id', @src, 'S.fname AS file_name',
            qw(
            S.de_id S.hash R.account_id R.contest_id R.problem_id R.judge_id
            R.state R.failed_test R.points R.tag
            R.submit_time R.test_time R.result_time
            ),
            "(R.submit_time - $CATS::Time::contest_start_offset_sql) AS time_since_start",
            'DE.description AS de_name',
            'A.team_name', 'COALESCE(E.ip, A.last_ip) AS last_ip',
            'P.title AS problem_name', 'P.save_output_prefix',
            'P.contest_id AS orig_contest_id',
            @pc_sql,
            @limits, 'R.limits_id as limits_id',
            'C.title AS contest_name',
            'C.is_official',
            'COALESCE(R.testsets, CP.testsets) AS testsets',
            'CP.id AS cp_id',
            'CP.status', 'CP.code',
            'CA.id AS ca_id',
        ],
        tables => [
            'LEFT JOIN sources S ON S.req_id = R.id',
            'LEFT JOIN default_de DE ON DE.id = S.de_id',
            'INNER JOIN accounts A ON A.id = R.account_id',
            'INNER JOIN problems P ON P.id = R.problem_id',
            'INNER JOIN contests C ON C.id = R.contest_id',
            'INNER JOIN contest_problems CP ON CP.contest_id = C.id AND CP.problem_id = P.id',
            'LEFT JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = A.id',
            'LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id',
            'LEFT JOIN events E ON E.id = R.id',
            'LEFT JOIN limits LCP ON LCP.id = CP.limits_id',
            'LEFT JOIN limits LR ON LR.id = R.limits_id',
        ]
    });
    $dbh->{ib_enable_utf8} = 1;  # Resume "normal" operation.

    # User must be either jury or request owner to access a request.
    # Cache is_jury_in_contest since it requires a database request.
    my %jury_cache;
    my $is_jury_cached = sub {
        $jury_cache{$_[0]} //= is_jury_in_contest(contest_id => $_[0]) ? 1 : 0
    };

    for (keys %$req_tree) {
        my $r = $req_tree->{$_};
        ($r->{is_jury} = $is_jury_cached->($r->{contest_id})) || ($r->{account_id} == ($uid || 0))
            or delete $req_tree->{$_};
    }

    my %user_cache;
    my $user_cached = sub { $user_cache{$_[0]} //= _get_user_details($_[0]) };

    my $official = $opts{get_source} && CATS::Contest::current_official;
    $official = 0 if $official && $is_jury_cached->($official->{id});
    my $se = encoding_param('src_enc', 'WINDOWS-1251');

    for my $r (values %$req_tree) {
        $_ = Encode::decode_utf8($_) for @$r{'tag', grep /_name$/, keys %$r};

        my %additional_info = (
            CATS::IP::linkify_ip($r->{last_ip}),
            href_stats => url_f('user_stats', uid => $r->{account_id}),
            (href_send_message => $r->{ca_id} ? url_f('send_message_box', caid => $r->{ca_id}) : undef),
        );

        # We need to save original hash reference
        $r->{$_} = $additional_info{$_} for keys %additional_info;

        my $ss = $CATS::Verdicts::state_to_name->{$r->{state}};
        $r->{short_state} = $r->{is_jury} ? $ss :
            $CATS::Verdicts::hidden_verdicts_self->{$ss} // $ss;

        # Just hour and minute from testing start and finish timestamps.
        ($r->{"${_}_short"} = $r->{$_}) =~ s/^(.*)\s+(\d\d:\d\d)\s*$/$2/
            for qw(test_time result_time);
        $r->{formatted_time_since_start} = CATS::Time::format_diff($r->{time_since_start});

        get_nearby_attempt($r, 'prev', '<', 'DESC', 1, $opts{extra_params});
        get_nearby_attempt($r, 'next', '>', 'ASC' , 0, $opts{extra_params});
        # During the official contest, viewing sources from other contests
        # is disallowed to prevent cheating.
        if ($official && $official->{id} != $r->{contest_id}) {
            $r->{src} = res_str(1138, $official->{title});
        }
        elsif ($opts{encode_source}) {
            if (encodings()->{$se} && $r->{file_name} && $r->{file_name} !~ m/\.zip$/) {
                Encode::from_to($r->{src}, $se, 'utf-8');
                $r->{src} = Encode::decode_utf8($r->{src});
            }
        }
        $r->{status_name} = CATS::Messages::problem_status_names->{$r->{status}};

        if ($r->{elements_count} == 1) {
            $r->{$_} = $r->{elements}->[0]->{$_}
                for qw(file_name de_id de_name), $opts{get_source} ? qw(src syntax) : ();
        }

        $r->{file_name} //= '';
        $r->{src} //= '';
        $r->{de_id} //= 0;
        $r->{$_} = $r->{"lr_$_"} || $r->{"lcp_$_"} || $r->{"p_$_"} for @cats::limits_fields;

        $r->{can_reinstall} = $is_root || $r->{orig_contest_id} == $r->{contest_id};

        $r->{contacts} = $user_cached->($r->{account_id})->{contacts} if $r->{is_jury};
    }

    return ref $rid ? [ map { $req_tree->{$_} // () } @req_ids ] : $req_tree->{$rid};
}

sub build_title_suffix {
    my ($si) = @_;
    my %fn;
    $fn{$_->{file_name}}++ for @$si;
    join ',', map $_ . ($fn{$_} > 1 ? "*$fn{$_}" : ''), sort keys %fn;
}

sub sources_info_param {
    my ($sources_info) = @_;

    my $set_data;
    $set_data = sub {
        for my $si (@{$_[0]}) {
            $si->{style_classes} = { map {
                $_ => $si->{"lr_$_"} ? 'req_overridden_limits' :
                $si->{"lcp_$_"} ? 'cp_overridden_limits' : undef
            } @cats::limits_fields };
            $si->{req_overidden_limits} = {
                map { $_ => $si->{"lr_$_"} ? 1 : 0 } @cats::limits_fields
            };
            $si->{colspan} = scalar(@{$si->{elements}}) || 1;
            if ($si->{elements_count} == 1) {
                $si->{original_req_id} = $si->{elements}->[0]->{req_id};
                $si->{original_team_name} = $si->{elements}->[0]->{team_name};
            }
            $set_data->($si->{elements}) if $si->{elements_count};
        }
    };
    $set_data->($sources_info);
    $t->param(
        title_suffix => build_title_suffix($sources_info),
        sources_info => $sources_info
    );
    my $elements_info = [
        map { @{$_->{elements}} > 0 ? @{$_->{elements}} : undef } @$sources_info ];
    if (0 < grep $_, @$elements_info) {
        $t->param(elements_info => $elements_info);
    }
}

sub get_judges {
    my ($si) = @_;
    $t->param('judges') or $t->param(judges => $dbh->selectall_arrayref(q~
        SELECT id, nick, pin_mode FROM judges ORDER BY nick~, { Slice => {} }));
    $si->{judges} = [ {}, map {
        value => $_->{id},
        text => $_->{nick} . ($_->{pin_mode} == $cats::judge_pin_locked ? '' : ' *'),
        selected => ($_->{id} == ($si->{judge_id} || 0) ? $si->{judge_name} = $_->{nick} : 0),
    }, @{$t->param('judges')} ];
}

sub source_links {
    my ($si) = @_;
    my ($current_link) = url_param('f') || '';

    return if $si->{href_contest};

    $si->{href_contest} =
        url_function('problems', cid => $si->{contest_id}, sid => $sid);
    $si->{href_problem_text} =
        url_function('problem_text', cpid => $si->{cp_id}, cid => $si->{contest_id}, sid => $sid);
    $si->{href_problem_details} =
        url_function('problem_details', pid => $si->{problem_id}, cid => $si->{contest_id}, sid => $sid);
    if ($si->{elements_count} == 1) {
        my $original_req = $si->{elements}->[0];
        $si->{href_original_req_run_details} =
            url_f('run_details', rid => $original_req->{req_id});
        $si->{href_original_stats} =
            url_f('user_stats', uid => $original_req->{account_id});
    }
    for (qw/run_details view_source run_log download_source view_test_details request_params/) {
        $si->{"href_$_"} = url_f($_, rid => $si->{req_id});
        $si->{"href_class_$_"} = $_ eq $current_link ? 'current_link' : '';
    }
    $t->param(is_any_jury => 1) if $si->{is_jury};
    get_judges($si) if $si->{is_jury};
    my $se = param('src_enc') || param('comment_enc') || 'WINDOWS-1251';
    $t->param(source_encodings => source_encodings($se));

    source_links($_) for @{$si->{elements}};
}

sub get_log_dump {
    my ($rid, $compile_error) = @_;
    my ($dump, $length) = $dbh->selectrow_array(qq~
        SELECT SUBSTRING(dump FROM 1 FOR 500000), OCTET_LENGTH(dump)
        FROM log_dumps WHERE req_id = ?~, undef,
        $rid) or return ();
    $dump = Encode::decode_utf8($dump);
    ($dump) = $dump =~ m/
        \Q$cats::log_section_start_prefix$cats::log_section_compile\E
       (.*)
        \Q$cats::log_section_end_prefix$cats::log_section_compile\E
        /sx if $compile_error;
    return (judge_log_dump => $dump, judge_log_length => $length);
}

1;
