package CATS::UI::Contests;

use strict;
use warnings;

use CATS::Config;
use CATS::Constants;
use CATS::Contest::Participate qw(get_registered_contestant is_jury_in_contest);
use CATS::Contest;
use CATS::Contest::Utils;
use CATS::Contest::XmlSerializer;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $t $uid $user);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::Problem::Save;
use CATS::Problem::Storage;
use CATS::RankTable;
use CATS::Redirect;
use CATS::Settings qw($settings);
use CATS::StaticPages;
use CATS::Utils;
use CATS::Verdicts;

sub contests_new_frame {
    my ($p) = @_;
    $user->privs->{create_contests} or return;
    init_template($p, 'contests_new.html.tt');

    my $date = $dbh->selectrow_array(q~
        SELECT CURRENT_TIMESTAMP FROM RDB$DATABASE~);
    $date =~ s/\s*$//;
    my $verdicts = [ map +{ short => $_->[0], checked => 0 }, @$CATS::Verdicts::name_to_state_sorted ];
    $t->param(
        start_date => $date,
        finish_date => $date,
        can_edit => 1,
        is_hidden => !$is_root,
        show_all_results => 1,
        href_action => url_f('contests'),
        verdicts_max_reqs => $verdicts,
        verdicts_penalty => $verdicts,
        href_find_tags => url_f('api_find_contest_tags'),
    );

}

sub contest_params() {qw(
    rules title closed penalty max_reqs is_hidden local_only show_sites show_flags
    start_date short_descr is_official finish_date run_all_tests req_selection show_packages
    show_all_tests freeze_date defreeze_date show_test_data max_reqs_except show_frozen_reqs show_all_results
    pinned_judges_only show_test_resources show_checker_comment
    pub_reqs_date show_all_for_solved apikey login_prefix
)}

sub contest_checkbox_params() {qw(
    free_registration run_all_tests
    show_all_tests show_test_resources show_checker_comment show_all_results show_flags
    is_official show_packages local_only is_hidden show_test_data pinned_judges_only show_sites
    show_all_for_solved
)}

sub contest_string_params() {qw(
    title short_descr start_date freeze_date finish_date defreeze_date pub_reqs_date
    rules req_selection max_reqs
)}

sub get_contest_html_params {
    my ($p) = @_;
    my $c = { map { $_ => $p->{$_} } contest_string_params(), 'penalty' };
    $c->{$_} = $p->{$_} ? 1 : 0 for contest_checkbox_params();

    for ($c->{title}) {
        $_ //= '';
        s/^\s+|\s+$//g;
        $_ ne '' && length $_ < 100  or return msg(1027);
    }
    $c->{closed} = $c->{free_registration} ? 0 : 1;
    delete $c->{free_registration};
    $c->{show_frozen_reqs} = 0;

    for my $e (qw(max_reqs penalty)) {
        my $val = join ',', sort { $a <=> $b }
            grep $_, map $CATS::Verdicts::name_to_state->{$_}, @{$p->{"exclude_verdict_$e"}};
        $c->{$e . '_except'} = $val || undef;
    }
    $c;
}

sub _validate {
    my ($c) = @_;

    if (!$is_root) {
        delete $c->{_} for qw(apikey login_prefix);
    }

    my $req_fields = [
        { f => 'start_date', n => 600 },
        { f => 'finish_date', n => 631 },
    ];
    if (my @req_errors = grep !$c->{$_->{f}}, @$req_fields) {
        msg(1207, res_str($_->{n})) for @req_errors;
        return;
    }
    $c->{freeze_date} ||= $c->{finish_date};
    $c->{defreeze_date} ||= $c->{finish_date};
    {
        my $d = 'CAST(? AS TIMESTAMP)';
        my $check_after = qq~CASE WHEN $d <= $d THEN 1 ELSE 0 END,~;
        my $check_pub_reqs_date = $c->{pub_reqs_date} ? $check_after : '1,';
        my @flags = $dbh->selectrow_array(qq~
            SELECT
                $check_after
                $check_after
                $check_pub_reqs_date
                CASE WHEN $d BETWEEN $d AND $d THEN 1 ELSE 0 END
            FROM RDB\$DATABASE~, undef,
            @$c{
                qw(start_date finish_date),
                qw(freeze_date defreeze_date),
                ($c->{pub_reqs_date} ? qw(start_date pub_reqs_date) : ()),
                qw(freeze_date start_date finish_date),
            });
        if (my @errors = grep !$flags[$_], 0 .. $#flags) {
            my @msgs = (1183, 1185, 1202, 1184);
            msg($_) for @msgs[@errors];
            return;
        }
    }
    1;
}

sub contests_new_save {
    my ($p) = @_;
    my $c = get_contest_html_params($p) or return;
    _validate($c) or return;
    $c->{ctype} = 0;
    $c->{id} = new_id;
    $is_root or $c->{is_official} = 0;

    if ($p->{original_id}) {
        # Make sure the title of copied contest differs from the original.
        my ($original_title) = $dbh->selectrow_array(q~
            SELECT title FROM contests WHERE id = ?~, undef,
            $p->{original_id});
        if ($original_title && $original_title eq Encode::decode_utf8($c->{title})) {
            $c->{title} =~ s/\((\d+)\)$/(@{[ $1 + 1 ]})/ or $c->{title} .= ' (1)';
        }
    }
    eval { $dbh->do(_u $sql->insert('contests', $c)); 1 } or return msg(1026, $@);

    # Automatically register all admins as jury.
    my $root_accounts = CATS::Privileges::get_root_account_ids;
    push @$root_accounts, $uid unless $is_root; # User with contests_creator role.
    for (@$root_accounts) {
        $contest->register_account(
            contest_id => $c->{id}, account_id => $_, is_jury => 1, is_pop => 1, is_hidden => 1,
            ($_ == $uid ? (is_admin => 1) : ()));
    }

    if ($is_root && $p->{tag_name}) {
        my $tag_id = $dbh->selectrow_array(q~
            SELECT id FROM contest_tags WHERE name = ?~, undef,
            $p->{tag_name});
        $dbh->do(_u $sql->insert(contest_contest_tags => { contest_id => $c->{id}, tag_id => $tag_id }))
            if $tag_id;
    }

    $dbh->commit;
    msg(1028, Encode::decode_utf8($c->{title}));
}

sub _install_problems {
    my ($problems_to_install) = @_;
    my $jobs_created = 0;
    for my $judge_id (keys %$problems_to_install) {
        for (@{$problems_to_install->{$judge_id}}) {
            ++$jobs_created;
            CATS::Job::create($cats::job_type_initialize_problem, {
                judge_id => $judge_id,
                problem_id => $_,
                contest_id => $cid,
            })
        }
    }

    $dbh->commit;
    msg(1170, $jobs_created);
}

sub contest_problems_installed_frame {
    my ($p) = @_;

    $is_jury or return;

    init_template($p, 'contest_problems_installed.html.tt');

    my $pinned_judges_only = $dbh->selectrow_array(q~
        SELECT pinned_judges_only FROM contests WHERE id = ?~, undef,
        $cid);

    my $pin_any_cond = $pinned_judges_only ? '' : "J.pin_mode = $cats::judge_pin_any OR";

    my $judges = $dbh->selectall_arrayref(qq~
        SELECT J.id, J.nick FROM judges J
        WHERE J.is_alive = 1 AND
            ($pin_any_cond
                J.pin_mode = $cats::judge_pin_contest AND EXISTS (
                    SELECT 1 FROM contest_accounts CA
                    WHERE CA.account_id = J.account_id AND CA.contest_id = ?
                )
            )
        ORDER BY J.nick~, { Slice => {} },
        $cid);

    my $problems = $dbh->selectall_arrayref(q~
        SELECT P.id, P.title, CP.code FROM problems P
        INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE CP.contest_id = ?
        ORDER BY CP.code~, { Slice => {} },
        $cid);

    my $already_installed = $dbh->selectall_arrayref(qq~
        SELECT J.id as judge_id , P.id as problem_id, JB.finish_time FROM jobs JB
        INNER JOIN judges J on J.id = JB.judge_id
        INNER JOIN problems P on P.id = JB.problem_id
        INNER JOIN contest_problems CP on CP.problem_id = P.id
        WHERE JB.type = $cats::job_type_initialize_problem AND
            JB.state = $cats::job_st_finished AND
            P.upload_date < JB.finish_time AND CP.contest_id = ?~, { Slice => {} },
        $cid);

    my $judge_problems = {};
    $judge_problems->{$_->{judge_id}}->{$_->{problem_id}} = $_->{finish_time} for @$already_installed;

    my $problems_to_install = { map { $_->{id} => [] } @$judges };

    my $problems_installed = [ map {
        my $judge_id = $_->{id};
        my $hr = $judge_problems->{$judge_id} || {};
        {
            judge_name => $_->{nick},
            ($is_root ? (href_judge => url_f('judges_edit', id => $judge_id)) : ()),
            row => [ map {
                push @{$problems_to_install->{$judge_id}}, $_->{id}
                    if !$hr->{$_->{id}} && $p->{install_missing};
                {
                    judge_problem => $judge_id . '_' . $_->{id},
                    value => $hr->{$_->{id}} || '-'
                }
            } @$problems ],
        }
    } @$judges ];


    if ($p->{install_selected}) {
        for (@{$p->{selected_problems}}) {
            my ($judge_id, $problem_id) = split /_/, $_;
            push @{$problems_to_install->{$judge_id}}, $problem_id;
        }
    }

    _install_problems($problems_to_install) if $p->{install_missing} || $p->{install_selected};

    $t->param(
        problems_installed => $problems_installed,
        problems => $problems,
        href_action => url_f('contest_problems_installed', id => $cid)
    );

    CATS::Contest::Utils::contest_submenu('contest_problems_installed', $cid);
}

sub contest_params_frame {
    my ($p) = @_;

    init_template($p, 'contest_params.html.tt');
    $p->{id} //= $cid;

    my $c = $dbh->selectrow_hashref(q~
        SELECT * FROM contests WHERE id = ?~, { Slice => {} },
        $p->{id}) or return;
    $c->{free_registration} = !$c->{closed};

    my %verdicts_excluded_max_reqs =
        map { $CATS::Verdicts::state_to_name->{$_} => 1 } split /,/, $c->{max_reqs_except} // '';
    my %verdicts_excluded_penalty =
        map { $CATS::Verdicts::state_to_name->{$_} => 1 } split /,/, $c->{penalty_except} // '';

    my $is_jury_in_contest = is_jury_in_contest(contest_id => $p->{id});
    $t->param(
        %$c,
        href_action => url_f('contests'),
        can_edit => $is_jury_in_contest,
        href_api_login_token => (
            $is_root && $c->{apikey} ?
            CATS::Utils::url_function('api_login_token',
                apikey => $c->{apikey}, login => ($c->{login_prefix} // '') . 'XXXX',
                cid => $cid, redir => CATS::Redirect::encode({ f => 'problems' })) : undef),
        verdicts_max_reqs => [ map +{ short => $_->[0], checked => $verdicts_excluded_max_reqs{$_->[0]} },
            @$CATS::Verdicts::name_to_state_sorted ],
        verdicts_penalty => [ map +{ short => $_->[0], checked => $verdicts_excluded_penalty{$_->[0]} },
            @$CATS::Verdicts::name_to_state_sorted ],
    );
    CATS::Contest::Utils::contest_submenu('contest_params', $p->{id}) if $is_jury_in_contest;

    1;
}

sub contests_edit_save_xml {
    my ($p) = @_;
    $is_jury or return;

    my $logger = CATS::Problem::Storage->new;
    $t->param(logger => $logger);
    my $s = CATS::Contest::XmlSerializer->new(logger => $logger);
    my $c;
    eval {
        $c = $s->parse_xml($p->{contest_xml});
        $c->{id} = $cid;
        1;
    } or return $logger->note($@);

    contests_edit_save($c, { map { $_ => $c->{$_} } contest_params });

    if (@{$c->{tags}}) {
        $dbh->do(q~
            DELETE FROM contest_contest_tags WHERE contest_id = ?~, undef,
            $cid);
        my $insert_sth = $dbh->prepare(q~
            INSERT INTO contest_contest_tags
            SELECT ?, id FROM contest_tags WHERE name = ?~);
        $insert_sth->execute($cid, $_) for @{$c->{tags}};
        $dbh->commit;
    }

    for my $problem (@{$c->{problems}}) {
        if ($problem->{problem_id}) {
            ($problem->{contest_id} // $cid) == $cid
                or $logger->note(sprintf('Problem %d is from different context', $problem->{problem_id})), next;
            my %cp_update_values = %$problem;
            delete $cp_update_values{$_} for qw(repo_path repo_url allow_des);
            $dbh->do(_u $sql->update('contest_problems', \%cp_update_values,
                { contest_id => $cid, problem_id => $problem->{problem_id} }));

            my ($cpid) = $dbh->selectrow_array(q~
                SELECT CP.id FROM contest_problems CP
                WHERE CP.contest_id = ? AND CP.problem_id = ?~, undef,
                $cid, $problem->{problem_id});
            $cpid or $logger->note(sprintf('Problem not found: %d', $problem->{problem_id})), next;
            CATS::Problem::Save::set_contest_problem_des($cpid, $problem->{allow_des} || [], 'code');
            $dbh->commit;
        }
        else {
            $problem->{remote_url}
                or $logger->note("No remote url specified for problem $problem->{code}") and next;
            $logger->note(CATS::Problem::Save::problems_add_new_remote($problem));
        }
    }
}

sub contests_edit_save {
    my ($p, $c) = @_;
    _validate($c) or return;
    $is_root or delete $c->{is_official};
    eval {
        $dbh->do(_u $sql->update(contests => $c, { id => $p->{id} }));
        $dbh->commit;
        1;
    } or return msg(1035, $@);
    CATS::StaticPages::invalidate_problem_text(cid => $p->{id}, all => 1);
    CATS::RankTable::remove_cache($p->{id});
    my $contest_name = Encode::decode_utf8($c->{title});
    # Change page title immediately if the current contest is renamed.
    $contest->{title} = $contest_name if $p->{id} == $cid;
    msg(1036, $contest_name);
}

sub contest_delete {
    my ($delete_cid) = @_;
    $is_root or return;
    my ($cname, $problem_count) = $dbh->selectrow_array(q~
        SELECT title, (SELECT COUNT(*) FROM contest_problems CP WHERE CP.contest_id = C.id) AS pc
        FROM contests C WHERE C.id = ?~, undef,
        $delete_cid);
    $cname or return;
    return msg(1038, $cname, $problem_count) if $problem_count;
    $dbh->do(q~
        DELETE FROM contests WHERE id = ?~, undef,
        $delete_cid);
    $dbh->commit;
    $delete_cid == $cid || msg(1037, $cname);
}

sub contests_submenu_filter {
    my $f = $settings->{contests}->{filter} || '';
    {
        all => '',
        official => 'AND C.is_official = 1 ',
        unfinished => 'AND CURRENT_TIMESTAMP <= finish_date ',
        current => 'AND CURRENT_TIMESTAMP BETWEEN start_date AND finish_date ',
        ($uid ? (my =>
            "AND EXISTS(SELECT 1 FROM contest_accounts CA
            WHERE CA.contest_id = C.id AND CA.account_id = $uid)") : ()),
        json => q~
            AND EXISTS (
                SELECT 1 FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
                WHERE CP.contest_id = C.id AND P.json_data IS NOT NULL)~,
    }->{$f} || '';
}

sub _abs_url_f { $CATS::Config::absolute_url . CATS::Utils::url_function(@_) }

sub contests_rss_frame {
    my ($p) = @_;
    init_template($p, 'contests_rss.xml.tt');
    my $contests = $dbh->selectall_arrayref(q~
        SELECT id, title, short_descr, start_date
        FROM contests
        WHERE is_official = 1 AND is_hidden = 0
        ORDER BY start_date DESC ROWS 100~, { Slice => {} });
    for my $c (@$contests) {
        $c->{start_date_rfc822} = CATS::Utils::date_to_rfc822($c->{start_date});
        $c->{href_link} = _abs_url_f('problems', cid => $c->{id});
    }
    $t->param(href_root => $CATS::Config::absolute_url, contests => $contests);
}

sub _contests_set_tags {
    my ($p) = @_;
    my $tag_id = $dbh->selectrow_array(q~
        SELECT id FROM contest_tags WHERE name = ?~, undef,
        $p->{tag_name}) or return;
    my $count = 0;
    my $existing_sth = $dbh->prepare(q~
        SELECT 1 FROM contest_contest_tags WHERE contest_id = ? AND tag_id = ?~);
    my $insert_sth = $dbh->prepare(q~
        INSERT INTO contest_contest_tags (contest_id, tag_id) VALUES (?, ?)~);
    for (@{$p->{contests_selection}}) {
        $existing_sth->finish;
        $existing_sth->execute($_, $tag_id);
        my @r = $existing_sth->fetchrow_array and next;
        $insert_sth->execute($_, $tag_id);
        ++$count;
    }
    $dbh->commit;
    msg(1189, $count);
}

sub _contests_add_children {
    my ($p) = @_;
    my $count = 0;
    my $update_sth = $dbh->prepare(q~
        UPDATE contests SET parent_id = ?
        WHERE id = ? AND parent_id IS DISTINCT FROM ?~);
    for (@{$p->{contests_selection}}) {
        next if $_ == $cid;
        $count += $update_sth->execute($cid, $_, $cid);
    }
    $dbh->commit;
    msg(1193, $count);
}

sub _contests_remove_children {
    my ($p) = @_;
    my $count = 0;
    my $update_sth = $dbh->prepare(q~
        UPDATE contests SET parent_id = NULL
        WHERE id = ? AND parent_id = ?~);
    for (@{$p->{contests_selection}}) {
        next if $_ == $cid;
        $count += $update_sth->execute($_, $cid);
    }
    $dbh->commit;
    msg(1194, $count);
}

sub contests_frame {
    my ($p) = @_;

    if ($p->{summary_rank}) {
        return $p->redirect(url_f 'rank_table', clist => join ',', @{$p->{contests_selection}});
    }

    return if $p->{ical} && $p->{json};
    init_template($p, 'contests.' . ($p->{ical} ? 'ics' : $p->{json} ? 'json' : 'html') . '.tt');
    $p->{listview} = my $lv = CATS::ListView->new(web => $p, name => 'contests', url => url_f('contests'));

    CATS::Contest::contest_group_auto_new($p->{contests_selection})
        if $p->{create_group} && $is_root;

    contest_delete($p->{'delete'}) and return $p->redirect(url_f 'contests') if $p->{'delete'};

    contests_new_save($p) if $p->{new_save} && $user->privs->{create_contests};
    contests_edit_save($p, get_contest_html_params($p))
        if $p->{edit_save} && $p->{id} && is_jury_in_contest(contest_id => $p->{id});

    CATS::Contest::Participate::online if $p->{online_registration};
    CATS::Contest::Participate::virtual if $p->{virtual_registration};

    if ($is_root) {
        _contests_set_tags($p) if $p->{set_tags} && $p->{tag_name};
        _contests_add_children($p) if $p->{add_children};
        _contests_remove_children($p) if $p->{remove_children};
    }

    $lv->default_sort('Sd', 1)->define_columns([
        { caption => res_str(601), order_by => 'ctype DESC, title', width => '40%' },
        ($is_root ? { caption => res_str(663), order_by => 'ctype DESC, problems_count', width => '5%', col => 'Pc' } : ()),
        { caption => res_str(600), order_by => 'ctype DESC, start_date', width => '15%', col => 'Sd' },
        { caption => res_str(631), order_by => 'ctype DESC, finish_date', width => '15%', col => 'Fd' },
        { caption => res_str(630), order_by => 'ctype DESC, closed', width => '30%', col => 'Nt' },
        ($uid ? { caption => res_str(629), order_by => 'tags', width => '10%', col => 'Tg' } : ()),
    ]);

    $settings->{contests}->{filter} = my $filter =
        $p->{filter} || $settings->{contests}->{filter} || 'unfinished';

    $p->{filter_sql} = contests_submenu_filter;
    $lv->attach(
        defined $uid ?
            CATS::Contest::Utils::authenticated_contests_view($p) :
            CATS::Contest::Utils::anonymous_contests_view($p),
        ($uid ? () : { page_params => { filter => $filter } }));

    my $submenu = [
        map({
            href => url_f('contests', page => 0, filter => $_->{n}),
            item => res_str($_->{i}),
            selected => $filter eq $_->{n},
        },
            { n => 'all', i => 558 },
            { n => 'official', i => 559 },
            { n => 'unfinished', i => 560 },
            { n => 'my', i => 407 },
        ),
        ($user->privs->{create_contests} ?
            { href => url_f('contests_new'), item => res_str(537), new => 1 } : ()),
        { href => url_f('contests',
            ical => 1, rows => 50, filter => $filter), item => res_str(562) },
        { href => url_function('contests_rss'), item => 'RSS' },
        { href => url_function('contests',
            filter => $filter, search => $settings->{contests}->{search}), item => res_str(400) },
    ];
    $t->param(
        submenu => $submenu,
        href_rss => _abs_url_f('contests_rss'),
        href_find_tags => url_f('api_find_contest_tags'),
        href_has_tag_named => url_f('contests', search => 'has_tag_named(%s)'),
        CATS::Contest::Participate::flags_can_participate,
    );
}

sub contest_xml_frame {
    my ($p) = @_;

    init_template($p, 'contest_xml.html.tt');
    $is_jury or return;

    contests_edit_save_xml($p) if $p->{edit_save_xml};

    my $c = $dbh->selectrow_hashref(q~
        SELECT * FROM contests WHERE id = ?~, { Slice => {} },
        $cid) or return;

    $c->{tags} = $dbh->selectall_arrayref(q~
        SELECT CT.name FROM contest_tags CT
        INNER JOIN contest_contest_tags CCT ON CT.id = CCT.tag_id
        WHERE CCT.contest_id = ? ORDER BY CT.name~, { Slice => {} },
        $cid);
    my $problems = $dbh->selectall_arrayref(q~
        SELECT (
            SELECT LIST(DD.code, ',')
            FROM contest_problem_des CPD  
            INNER JOIN default_de DD ON DD.id = CPD.de_id
            WHERE CPD.cp_id = CP.id
            ) as allow_des, CP.* 
        FROM contest_problems CP
        WHERE CP.contest_id = ?
        ORDER BY CP.code~, { Slice => {} },
        $cid
    );
    $t->param(
        contest_xml =>
            Encode::decode_utf8($p->{contest_xml}) //
            CATS::Contest::XmlSerializer->new->serialize($c, $problems),
        form_action => url_f('contest_xml'),
    );
    CATS::Contest::Utils::contest_submenu('contest_xml', $cid);
}

1;
