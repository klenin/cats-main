package CATS::ReqDetails;

use strict;
use warnings;

use Digest::SHA;
use MIME::Base64;

use CATS::Constants;
use CATS::Contest;
use CATS::Contest::Participate qw(is_jury_in_contest);
use CATS::DB qw(:DEFAULT $db);
use CATS::Globals qw($contest $is_jury $is_root $t $uid);
use CATS::Messages qw(res_str);
use CATS::Output qw(search url_f url_f_cid);
use CATS::Problem::Utils;
use CATS::Request;
use CATS::Time;
use CATS::Score;
use CATS::Settings qw($settings);
use CATS::Utils qw(encodings source_encodings);
use CATS::Verdicts;

use Exporter qw(import);
our @EXPORT_OK = qw(
    get_compilation_error
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
    my ($p, $si, $cache) = @_;

    $_ and return $_ for $cache->{$si->{contest_id}};

    my @show_fields = qw(show_all_tests show_test_resources show_checker_comment show_test_data);
    my $c = $cache->{$si->{contest_id}} = $si->{contest_id} == $contest->{id} ?
        { map { $_ => $contest->{$_} } 'id', 'run_all_tests', @show_fields, 'time_since_defreeze' } :
        CATS::DB::select_row('contests', [
            'id', 'run_all_tests', @show_fields,
            'CAST(CURRENT_TIMESTAMP - defreeze_date AS DOUBLE PRECISION) AS time_since_defreeze' ],
            { id => $si->{contest_id} });

    my $jury_view = $si->{is_jury} && !$p->{as_user};
    $c->{$_} ||= $jury_view for @show_fields;
    $c->{hide_testset_details} = !$jury_view && $c->{time_since_defreeze} < 0;

    $c;
}

sub get_contest_tests {
    my ($c, $problem_id) = @_;

    my $cut = $cats::test_file_cut + 1;
    my $fields = join ', ',
        ($c->{show_all_tests} ? 'T.points' : ()),
        ($c->{show_test_data} ? qq~
            (SELECT COALESCE(PSL.fname, PSLE.fname) FROM problem_sources PS
            LEFT JOIN problem_sources_local PSL on PSL.id = PS.id
            LEFT JOIN problem_sources_imported PSI on PSI.id = PS.id
            LEFT JOIN problem_sources_local PSLE on PSLE.guid = PSI.guid
            WHERE PS.id = T.generator_id) AS gen_name,
            T.descr, T.param, T.gen_group, T.snippet_name,
            T.in_file_size AS input_file_size, T.out_file_size AS answer_file_size,
            CAST(LEFT(T.in_file, $cut) AS VARCHAR($cut)) AS input,
            CAST(LEFT(T.out_file, $cut) AS VARCHAR($cut)) AS answer
            ~ : ());
    my $tests = $c->{tests} = $fields ?
        $dbh->selectall_arrayref(qq~
            SELECT $fields FROM tests T WHERE T.problem_id = ? ORDER BY T.rank~, { Slice => {} },
            $problem_id) : [];
    my $p = $c->{points} = $c->{show_all_tests} ? [ map $_->{points}, @$tests ] : [];
    $c->{show_points} = 0 != grep defined $_ && $_ > 0, @$p;

    $c;
}

sub get_test_data {
    my ($p) = @_;
    $dbh->selectrow_hashref(qq~
        SELECT
            T.in_file AS input, T.in_file_size AS input_size,
            COALESCE(T.out_file, CAST(
                (SELECT S.text FROM snippets S
                WHERE S.name = T.snippet_name AND
                    S.contest_id = R.contest_id AND
                    S.problem_id = R.problem_id AND
                    S.account_id = R.account_id
            ) AS $db->{BLOB_TYPE})) AS answer,
            T.out_file_size AS answer_size,
            T.snippet_name
        FROM tests T
        LEFT JOIN reqs R ON R.problem_id = T.problem_id
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

sub _get_nearby_attempt {
    my ($p, $si, $prevnext, $cmp, $ord, $diff, $extra_params) = @_;
    # TODO: Сheck neighbour's contest to ensure correct access privileges.
    my $na = $dbh->selectrow_hashref(qq~
        SELECT id, submit_time, state, points FROM reqs
        WHERE account_id = ? AND problem_id = ? AND id $cmp ?
        ORDER BY id $ord $db->{LIMIT} 1~, { Slice => {} },
        $si->{account_id}, $si->{problem_id}, $si->{req_id}
    ) or return;
    for ($na->{submit_time}) {
        s/\s*$//;
        # If the date is the same with the current run, display only time.
        my ($n_date, $n_time) = /^(\d+\.\d+\.\d+\s+)(.*)$/;
        $si->{"${prevnext}_attempt_time"} = $si->{submit_time} =~ /^$n_date/ ? $n_time : $_;
    }
    my @ep = $extra_params ? @$extra_params : ();
    if ($p->{f} eq 'diff_runs') {
        for (1..2) {
            my $r = $p->{"r$_"} // 0;
            push @ep, "r$_" => ($r == $si->{req_id} ? $na->{id} : $r);
        }
    }
    else {
        push @ep, (rid => $na->{id});
    }
    $si->{"href_${prevnext}_attempt"} = url_f($p->{f}, @ep);
    $si->{nearby}->{$prevnext} = $na;
    $na->{title} =
        $CATS::Verdicts::state_to_name->{$na->{state}} .
        (defined $na->{points} ? ' ' . CATS::Score::scale_points($na->{points}, $si) : '');
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

sub update_verdict {
    my ($r) = @_;
    $r->{short_state} = CATS::Verdicts::hide_verdict_self(
        $r->{is_jury}, $CATS::Verdicts::state_to_name->{$r->{state}});
}

sub _encode_source {
    my ($r, $se) = @_;
    $r->{mime_type} = $CATS::Globals::binary_exts->{ext_to_mime}->{$r->{ext}};
    $r->{is_binary} = defined $r->{mime_type};
    $r->{is_image} = defined $r->{mime_type} && $r->{mime_type} =~ /^image\//;
    encodings()->{$se} or return;
    if ($se eq 'HEX') {
        $r->{src} = CATS::Utils::hex_dump($r->{src}, 16);
    }
    elsif (!$r->{is_binary}) {
        Encode::from_to($r->{src}, $se, 'utf-8');
        $r->{src} = Encode::decode_utf8($r->{src});
    }
}

# Load information about one or several runs.
# Parameters: request_id, may be either scalar or array ref.
sub get_sources_info {
    my ($p, %opts) = @_;
    my $rid = $opts{request_id} or return;

    my @req_ids = ref $rid eq 'ARRAY' ? @$rid : ($rid);
    @req_ids = map +$_, grep $_ && /^\d+$/, @req_ids or return;

    my @src = $opts{get_source} ? (qw(S.src DE.syntax DE.err_regexp), 'OCTET_LENGTH(S.src) AS src_len') : ();

    my @limits = map { my $l = $_; map "$_.$l AS @{[$_]}_$l", qw(lr lcp p) } @cats::limits_fields;

    # Source code can be in arbitary or broken encoding, we need to decode it explicitly.
    $db->disable_utf8;

    my $req_tree = CATS::JudgeDB::get_req_tree(\@req_ids, {
        fields => [
            'R.id AS req_id', @src, 'S.fname AS file_name', 'S.hash AS db_hash',
            qw(
            S.de_id R.account_id R.contest_id R.problem_id R.judge_id
            R.state R.failed_test R.points R.tag
            R.submit_time R.test_time R.result_time
            ),
            "CAST(R.result_time - R.test_time AS DOUBLE PRECISION) AS test_duration",
            "CAST(R.submit_time - $CATS::Time::contest_start_offset_sql AS DOUBLE PRECISION) AS time_since_start",
            'DE.description AS de_name', 'DE.code AS de_code',
            'A.team_name', 'COALESCE(E.ip, A.last_ip) AS last_ip',
            'P.title AS problem_name', 'P.save_output_prefix',
            'P.contest_id AS orig_contest_id',
            @limits,
            'LR.job_split_strategy AS lr_job_split_strategy',
            'LCP.job_split_strategy AS lcp_job_split_strategy',
            'R.limits_id AS limits_id',
            'C.title AS contest_name',
            'C.is_official',
            'C.rules',
            'C.show_all_for_solved',
            'CAST(CURRENT_TIMESTAMP - C.pub_reqs_date AS DOUBLE PRECISION) AS time_since_pub_reqs',
            'COALESCE(R.testsets, CP.testsets) AS testsets',
            'CP.id AS cp_id',
            'CP.status', 'CP.code', 'CP.max_points', 'CP.scaled_points', 'CP.round_points_to',
            'CA.id AS ca_id', 'CA.is_jury AS submitter_is_jury', 'CA.is_hidden', 'CA.tag AS ca_tag',
            '(SELECT COUNT(*) FROM problem_snippets PSN WHERE PSN.problem_id = P.id) AS problem_snippets'
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
    $db->enable_utf8;  # Resume "normal" operation.

    # User must be either jury or request owner to access a request.
    # Cache is_jury_in_contest since it requires a database request.
    my %jury_cache;
    my $is_jury_cached = sub {
        $jury_cache{$_[0]} //= is_jury_in_contest(contest_id => $_[0]) ? 1 : 0
    };

    my %solved;
    my $is_solved = sub {
        my ($r) = @_;
        my $max_points_cond = $r->{rules} ? ' AND R.points = CP.max_points' : '';
        $solved{$r->{problem_id}} //= $r->{show_all_for_solved} && $dbh->selectrow_array(qq~
            SELECT 1 FROM reqs R
            WHERE
                R.contest_id = ? AND R.problem_id = ? AND R.account_id = ? AND
                R.state = $cats::st_accepted$max_points_cond $db->{LIMIT} 1~, undef,
            $r->{contest_id}, $r->{problem_id}, $uid)
    };

    my $can_see;
    for (keys %$req_tree) {
        my $r = $req_tree->{$_};
        $r->{sha1} = Digest::SHA::sha1_hex($r->{src} // '');
        $r->{src} = join "\n",
            map CATS::Similarity::preprocess_line({ collapse_idents => 1 }), split "\n", $r->{src}
            if $p->web_param('preprocess');
        $r->{is_jury} = $is_jury_cached->($r->{contest_id});
        $r->{is_jury} || $r->{account_id} == ($uid || 0) ||
            $p->{hash} && $p->{hash} eq $r->{sha1} ||
            ($r->{time_since_pub_reqs} // 0) > 0 && !$r->{submitter_is_jury} ||
            ($can_see //= $uid ? CATS::Request::can_see_by_relation($uid) : {})->{$r->{account_id}} ||
            $is_solved->($r)
            or delete $req_tree->{$_};
        $r->{$_} = $db->format_date($r->{$_}) for qw(submit_time test_time result_time)
    }

    my %user_cache;
    my $user_cached = sub { $user_cache{$_[0]} //= _get_user_details($_[0]) };

    my $current_official = $opts{get_source} && CATS::Contest::current_official;
    undef $current_official if $current_official && $is_jury_cached->($current_official->{id});
    my $se = $p->{src_enc};

    for my $r (values %$req_tree) {
        $_ = Encode::decode_utf8($_) for @$r{'tag', 'ca_tag', grep /_name$/, keys %$r};

        my %additional_info = (
            CATS::IP::linkify_ip($r->{last_ip}),
            href_stats => url_f('user_stats', uid => $r->{account_id}),
            (href_send_message => $r->{ca_id} ? url_f('send_message_box', caid => $r->{ca_id}) : undef),
        );

        # We need to save original hash reference
        $r->{$_} = $additional_info{$_} for keys %additional_info;

        update_verdict($r);
        $r->{href_quick_verdict} = url_f('request_params', rid => $r->{req_id});

        # Just hour and minute from testing start and finish timestamps.
        ($r->{"${_}_short"} = $r->{$_}) =~ s/^(.*)\s+(\d\d:\d\d)\s*$/$2/
            for qw(test_time result_time);
        $r->{formatted_time_since_start} = CATS::Time::format_diff($r->{time_since_start});

        _get_nearby_attempt($p, $r, 'prev', '<', 'DESC', 1, $opts{extra_params});
        _get_nearby_attempt($p, $r, 'next', '>', 'ASC' , 0, $opts{extra_params});

        $r->{file_name} //= '';
        $r->{file_name} =~ m/\.([^.]+)$/;
        $r->{ext} = lc($1 || '');

        # During the official contest, viewing sources from other contests
        # is disallowed to prevent cheating.
        if ($current_official && $r->{contest_id} != $current_official->{id}) {
            $r->{src} = res_str(1138, $current_official->{title}, $current_official->{finish_date});
        }
        elsif ($opts{encode_source}) {
            _encode_source($r, $se);
        }
        $r->{status_name} = CATS::Messages::problem_status_names->{$r->{status}};

        if ($r->{elements_count} == 1) {
            $r->{$_} = $r->{elements}->[0]->{$_}
                for qw(file_name de_id de_name de_code), $opts{get_source} ? qw(src syntax) : ();
        }

        $r->{src} //= '';
        $r->{de_id} //= 0;
        $r->{$_} = $r->{"lr_$_"} || $r->{"lcp_$_"} || $r->{"p_$_"} for @cats::limits_fields, 'job_split_strategy';
        CATS::Problem::Utils::round_time_limit($r->{time_limit});

        $r->{can_reinstall} = $is_root || $r->{orig_contest_id} == $r->{contest_id};

        $r->{contacts} = $user_cached->($r->{account_id})->{contacts} if $r->{is_jury};
        $r->{href_test_diff} = url_f_cid('test_diff',
            pid => $r->{problem_id}, test => $r->{failed_test}, cid => $r->{contest_id})
            if $r->{is_jury} && $r->{failed_test};

        $r->{scaled_points_v} = CATS::Score::scale_points($r->{points}, $r);

        $r->{href_snippets} = url_f_cid('snippets', cid => $r->{contest_id}, search(
            problem_id => $r->{problem_id},
            account_id => $r->{account_id},
            contest_id => $r->{contest_id},
        ));
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
            } @cats::limits_fields, 'job_split_strategy' };
            $si->{req_overidden_limits} = {
                map { $_ => $si->{"lr_$_"} ? 1 : 0 } @cats::limits_fields, 'job_split_strategy'
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
        sources_info => $sources_info,
        hidden_rows => { map { $_ => 1 } split ',', $settings->{sources_info}->{hidden_rows} // '' },
        unprocessed_sources => [ grep $_->{state} < $cats::request_processed, @$sources_info ],
        href_get_request_state => url_f('api_get_request_state'),
        href_modify_settings => url_f('api_modify_settings'),
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
    my ($p, $si) = @_;
    my ($current_link) = $p->{f};

    return if $si->{href_contest};

    $si->{href_contest} = url_f_cid('problems', cid => $si->{contest_id});
    $si->{href_problem_details} =
        url_f_cid('problem_details', pid => $si->{problem_id}, cid => $si->{contest_id});
    my $problem_text_uid = $si->{account_id};
    if ($si->{elements_count} == 1) {
        my $original_req = $si->{elements}->[0];
        $si->{href_original_req_run_details} =
            url_f('run_details', rid => $original_req->{req_id});
        $si->{href_original_stats} =
            url_f('user_stats', uid => $original_req->{account_id});
        $problem_text_uid = $original_req->{account_id};
    }
    $si->{href_problem_text} = url_f_cid('problem_text',
        cpid => $si->{cp_id}, cid => $si->{contest_id},
        ($si->{is_jury} ? (uid => $problem_text_uid) : ()),
        ($si->{is_jury} ? (rid => $si->{req_id}) : ()));
    for (qw/run_details view_source run_log download_source view_test_details request_params/) {
        $si->{"href_$_"} = url_f($_, rid => $si->{req_id});
        $si->{"href_class_$_"} = $_ eq $current_link ? 'current_link' : '';
    }
    if ($si->{is_jury}) {
        $t->param(is_any_jury => 1);
        get_judges($si);
    }
    my $se = $p->{src_enc} || $p->{comment_enc} || 'WINDOWS-1251';
    $t->param(source_encodings => source_encodings($se));

    source_links($p, $_) for @{$si->{elements}};
}

sub get_log_dump {
    my ($cond) = @_;
    my ($job_tree_sql, @bind) = CATS::Request::get_job_tree_sql($cond);

    my $logs = $dbh->selectall_arrayref(qq~
        $job_tree_sql
        SELECT
            J.id AS job_id, J.type, JD.nick AS judge_name,
            J.state, J.create_time, J.start_time, J.finish_time,
            J.testsets, J.parent_id, JS.src,
            SUBSTRING(L.dump FROM 1 FOR 500000) AS dump,
            OCTET_LENGTH(L.dump) AS "length"
        FROM jobs_tree JT
        INNER JOIN jobs J ON J.id = JT.id
        LEFT JOIN job_sources JS ON JS.job_id = J.id
        LEFT JOIN logs L ON L.job_id = J.id
        LEFT JOIN judges JD ON JD.id = J.judge_id
        ORDER BY J.id DESC~, { Slice => {} },
        @bind) or return [];

    for my $log (@$logs) {
        $log->{dump} = Encode::decode_utf8($log->{dump});
        $log->{$_} = $db->format_date($log->{$_})
            for qw(create_time start_time finish_time);
    }
    $logs;
}

sub get_compilation_error {
    my ($logs, $st) = @_;

    my $section = $st == $cats::st_compilation_error ? $cats::log_section_compile : $cats::log_section_lint;
    my $compilation_error_re = qr/
        \Q$cats::log_section_start_prefix$section\E
        (.*)
        \Q$cats::log_section_end_prefix$section\E
        /sx;
    for (@$logs) {
        $_->{dump} or next;
        my ($error) = $_->{dump} =~ $compilation_error_re;
        return $error if $error;
    }
    undef;
}

sub prepare_sources {
    my ($p, $sources_info) = @_;
    if ($sources_info->{is_binary}) {
        $sources_info->{src} = $sources_info->{is_image} || $sources_info->{mime_type} eq 'application/pdf' ?
            MIME::Base64::encode_base64($sources_info->{src}) :
            sprintf 'binary, %d bytes', $sources_info->{src_len};
    }
    if (my $r = $sources_info->{err_regexp}) {
        my (undef, undef, $file_name) = CATS::Utils::split_fname($sources_info->{file_name});
        CATS::Utils::sanitize_file_name($file_name);
        $file_name =~ s/([^a-zA-Z0-9_])/\\$1/g;
        for (split ' ', $r) {
            s/~FILE~/$file_name/;
            s/~LINE~/(\\d+)/;
            s/~POS~/\\d+/;
            push @{$sources_info->{err_regexp_js}}, "/$_/";
        }
    }
    $sources_info->{syntax} = $p->{syntax} if $p->{syntax};
    my $st = $sources_info->{state};
    if ($st == $cats::st_compilation_error || $st == $cats::st_lint_error) {
        my $logs = get_log_dump({ req_id => $sources_info->{req_id} });
        $sources_info->{compiler_output} = get_compilation_error($logs, $st)
    }
    $sources_info;
}

1;
