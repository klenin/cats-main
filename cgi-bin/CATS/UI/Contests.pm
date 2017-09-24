package CATS::UI::Contests;

use strict;
use warnings;

use CATS::Constants;
use CATS::Contest::Participate qw(get_registered_contestant is_jury_in_contest);
use CATS::Contest;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t $uid $user);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(auto_ext init_template url_f);
use CATS::RankTable;
use CATS::Settings qw($settings);
use CATS::StaticPages;
use CATS::Web qw(param url_param redirect);

sub contests_new_frame {
    init_template('contests_new.html.tt');

    my $date = $dbh->selectrow_array(q~
        SELECT CURRENT_TIMESTAMP FROM RDB$DATABASE~);
    $date =~ s/\s*$//;
    $t->param(
        start_date => $date, freeze_date => $date,
        finish_date => $date, defreeze_date => $date,
        can_edit => 1,
        is_hidden => !$is_root,
        show_all_results => 1,
        href_action => url_f('contests')
    );
}

sub contest_checkbox_params() {qw(
    free_registration run_all_tests
    show_all_tests show_test_resources show_checker_comment show_all_results show_flags
    is_official show_packages local_only is_hidden show_test_data pinned_judges_only
)}

sub contest_string_params() {qw(
    title short_descr start_date freeze_date finish_date defreeze_date rules req_selection max_reqs
)}

sub get_contest_html_params {
    my $p = {};

    $p->{$_} = scalar param($_) for contest_string_params();
    $p->{$_} = param($_) ? 1 : 0 for contest_checkbox_params();

    for ($p->{title}) {
        $_ //= '';
        s/^\s+|\s+$//g;
        $_ ne '' && length $_ < 100  or return msg(1027);
    }
    $p->{closed} = $p->{free_registration} ? 0 : 1;
    delete $p->{free_registration};
    $p->{show_frozen_reqs} = 0;
    $p;
}

sub contests_new_save {
    my $c = get_contest_html_params() or return;

    $c->{ctype} = 0;
    $c->{id} = new_id;
    eval { $dbh->do(_u $sql->insert('contests', $c)); 1 } or return msg(1026, $@);

    # Automatically register all admins as jury.
    my $root_accounts = CATS::Privileges::get_root_account_ids;
    push @$root_accounts, $uid unless $is_root; # User with contests_creator role.
    for (@$root_accounts) {
        $contest->register_account(
            contest_id => $c->{id}, account_id => $_, is_jury => 1, is_pop => 1, is_hidden => 1);
    }
    $dbh->commit;
    msg(1028, Encode::decode_utf8($c->{title}));
}

sub try_contest_params_frame {
    my $id = url_param('params') or return;

    init_template('contest_params.html.tt');

    my $c = $dbh->selectrow_hashref(q~
        SELECT * FROM contests WHERE id = ?~, { Slice => {} },
        $id) or return;
    $c->{free_registration} = !$c->{closed};
    $t->param(
        id => $id, %$c,
        href_action => url_f('contests'),
        can_edit => is_jury_in_contest(contest_id => $id),
    );

    1;
}

sub contests_edit_save {
    my ($edit_cid) = @_;

    my $c = get_contest_html_params() or return;
    eval {
        $dbh->do(_u $sql->update(contests => $c, { id => $edit_cid }));
        $dbh->commit;
        1;
    } or return msg(1035, $@);
    CATS::StaticPages::invalidate_problem_text(cid => $edit_cid, all => 1);
    CATS::RankTable::remove_cache($edit_cid);
    my $contest_name = Encode::decode_utf8($c->{title});
    # Change page title immediately if the current contest is renamed.
    $contest->{title} = $contest_name if $edit_cid == $cid;
    msg(1036, $contest_name);
}

sub contests_select_current {
    defined $uid or return;

    my ($registered, $is_virtual, $is_jury) = get_registered_contestant(
        fields => '1, is_virtual, is_jury', contest_id => $cid
    );
    return if $is_jury;

    $t->param(selected_contest_title => $contest->{title});

    if ($contest->{time_since_finish} > 0) {
        msg(1115, $contest->{title});
    }
    elsif (!$registered) {
        msg(1116);
    }
}

sub contest_delete {
    my $delete_cid = url_param('delete');
    $is_root or return;
    my ($cname, $problem_count) = $dbh->selectrow_array(q~
        SELECT title, (SELECT COUNT(*) FROM contest_problems CP WHERE CP.contest_id = C.id) AS pc
        FROM contests C WHERE C.id = ?~, undef,
        $delete_cid);
    $cname or return;
    return  msg(1038, $cname, $problem_count) if $problem_count;
    $dbh->do(q~
        DELETE FROM contests WHERE id = ?~, undef,
        $delete_cid);
    $dbh->commit;
    msg(1037, $cname);
}

sub contests_submenu_filter {
    my $f = $settings->{contests}->{filter} || '';
    {
        all => '',
        official => 'AND C.is_official = 1 ',
        unfinished => 'AND CURRENT_TIMESTAMP <= finish_date ',
        current => 'AND CURRENT_TIMESTAMP BETWEEN start_date AND finish_date ',
        json => q~
            AND EXISTS (
                SELECT 1 FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
                WHERE CP.contest_id = C.id AND P.json_data IS NOT NULL)~,
    }->{$f} || '';
}

sub contests_frame {
    my ($p) = @_;

    if ($p->{summary_rank}) {
        my @clist = param('contests_selection');
        return redirect(url_f('rank_table', clist => join ',', @clist));
    }

    return contests_new_frame
        if defined url_param('new') && $user->privs->{create_contests};

    try_contest_params_frame and return;

    my $ical = param('ical');
    my $json = param('json');
    return if $ical && $json;
    $p->{listview} = my $lv = CATS::ListView->new(name => 'contests',
        template => 'contests.' .  ($ical ? 'ics' : $json ? 'json' : 'html') . '.tt');

    CATS::Contest::contest_group_auto_new if $p->{create_group} && $is_root;

    contest_delete if url_param('delete');

    contests_new_save if $p->{new_save} && $user->privs->{create_contests};
    contests_edit_save($p->{id})
        if $p->{edit_save} && $p->{id} && is_jury_in_contest(contest_id => $p->{id});

    CATS::Contest::Participate::online if $p->{online_registration};
    CATS::Contest::Participate::virtual if $p->{virtual_registration};

    contests_select_current if defined url_param('set_contest');

    $lv->define_columns(url_f('contests'), 1, 1, [
        { caption => res_str(601), order_by => '1 DESC, 2', width => '40%' },
        { caption => res_str(600), order_by => '1 DESC, 5', width => '15%' },
        { caption => res_str(631), order_by => '1 DESC, 6', width => '15%' },
        { caption => res_str(630), order_by => '1 DESC, 9', width => '30%' } ]);

    $settings->{contests}->{filter} = my $filter =
        param('filter') || $settings->{contests}->{filter} || 'unfinished';

    $p->{filter} = contests_submenu_filter;
    $lv->attach(url_f('contests'),
        defined $uid ?
            CATS::Contest::Utils::authenticated_contests_view($p) :
            CATS::Contest::Utils::anonymous_contests_view($p),
        ($uid ? () : { page_params => { filter => $filter } }));

    my $submenu = [
        map({
            href => url_f('contests', page => 0, filter => $_->{n}),
            item => res_str($_->{i}),
            selected => $settings->{contests}->{filter} eq $_->{n},
        }, { n => 'all', i => 558 }, { n => 'official', i => 559 }, { n => 'unfinished', i => 560 }),
        ($user->privs->{create_contests} ?
            { href => url_f('contests', new => 1), item => res_str(537) } : ()),
        { href => url_f('contests',
            ical => 1, rows => 50, filter => $filter), item => res_str(562) },
    ];
    $t->param(
        submenu => $submenu,
        CATS::Contest::Participate::flags_can_participate,
    );
}

1;
