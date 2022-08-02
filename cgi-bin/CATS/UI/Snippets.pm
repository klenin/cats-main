package CATS::UI::Snippets;

use strict;
use warnings;

use Encode;

use CATS::DB;
use CATS::Globals qw($cid $is_jury $is_root $t $uid);
use CATS::Job;
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::TeX::Lite;

my $str1_200 = CATS::Field::str_length(1, 200);
my $str0_200 = CATS::Field::str_length(0, 200);

sub _validate_unique_snippet {
    my ($fd) = @_;
    my $sn = $fd->{indexed};
    my ($snippet_id) = $dbh->selectrow_array(q~
        SELECT id FROM snippets
        WHERE problem_id = ? AND account_id = ? AND contest_id = ? AND name = ?~, undef,
        map $sn->{$_}->{value}, qw(problem_id account_id contest_id name)
    );
    !$snippet_id || $snippet_id == ($fd->{id} // 0) or msg(1077, $sn->{name}->{value});
}

sub _submenu { $t->param(submenu => [ CATS::References::menu('snippets') ] ) }

sub _parse_login {
    my ($value, $p) = @_;
    return $value if $p->{js};
    $dbh->selectrow_array(q~
        SELECT id FROM accounts WHERE login = ?~, undef,
        $p->{login} // '') // 0;
}

sub _must_be_current_contest { ($_[0] || 0) != $cid and res_str(1182) }

our $form = CATS::Form->new(
    table => 'snippets',
    fields => [
        [ name => 'account_id', after_parse => \&_parse_login,
            validators => [ $CATS::Field::foreign_key ], caption => 608, ],
        [ name => 'problem_id', validators => [ $CATS::Field::foreign_key ], caption => 602 ],
        [ name => 'contest_id', default => sub { $cid },
            validators => [ $CATS::Field::foreign_key, \&_must_be_current_contest ], caption => 603, ],
        [ name => 'name', validators => [ $str1_200 ], caption => 601, ],
        [ name => 'text', caption => 672, editor => { cols => 100, rows => 5 }, ],
    ],
    href_action => 'snippets_edit',
    descr_field => 'name',
    template_var => 'sn',
    msg_deleted => 1076,
    msg_saved => 1075,
    validators => [ \&_validate_unique_snippet ],
    before_display => sub {
        my ($fd, $p) = @_;
        $fd->{problems} = $dbh->selectall_arrayref(q~
            SELECT P.id AS "value", CP.code || ': ' || P.title AS text
            FROM problems P INNER JOIN contest_problems CP ON P.id = CP.problem_id
            WHERE CP.contest_id = ?
            ORDER BY CP.code~, { Slice => {} },
            $cid);
        if (((my $snippet_cid = $fd->{indexed}->{contest_id}->{value}) // 0) != $cid) {
            $fd->{contest_name} = $dbh->selectrow_array(q~
                SELECT title FROM contests WHERE id = ?~, undef,
                $snippet_cid);
        }
        if (my $aid = $fd->{indexed}->{account_id}->{value}) {
            ($fd->{login}, $fd->{team_name}) = $dbh->selectrow_array(q~
                SELECT login, team_name FROM accounts WHERE id = ?~, undef,
                $aid);
        }
        $fd->{href_find_users} = url_f('api_find_users');
        _submenu;
    },
);

sub snippets_edit_frame {
    my ($p) = @_;
    init_template($p, 'snippets_edit.html.tt');
    $is_jury or return;
    $form->edit_frame($p, redirect => [ 'snippets' ]);
}

sub _problem_visible {
    my ($cpid) = @_;
    return 1 if $is_root;

    my $c = $dbh->selectrow_hashref(qq~
        SELECT
            CAST(CURRENT_TIMESTAMP - $CATS::Time::contest_start_offset_sql AS DOUBLE PRECISION) AS since_start,
            C.local_only, C.is_hidden, CA.id AS caid, CA.is_jury, CA.is_remote, CA.is_ooc, CP.status
        FROM contest_problems CP INNER JOIN contests C ON CP.contest_id = C.id
        LEFT JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
        LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
        WHERE CP.id = ?~, undef,
    $uid, $cpid) or return 0;

    return 1 if $c->{is_jury};

    $c->{status} < $cats::problem_st_hidden or return 0;

    if (($c->{since_start} || 0) > 0 && (!$c->{is_hidden} || $c->{caid})) {
        $c->{local_only} or return 1;
        defined $uid or return 0;
        return 1 if defined $c->{is_remote} && $c->{is_remote} == 0 || defined $c->{is_ooc} && $c->{is_ooc} == 0;
    }

    0;
}

sub get_snippets {
    my ($p) = @_;

    $uid && _problem_visible($p->{cpid}) or return $p->print_json({});

    my $account_id = $p->{uid} && $is_jury ? $p->{uid} : $uid;

    my $snippets = $dbh->selectall_arrayref(my @d = _u $sql->select(q~
        snippets S
        INNER JOIN contest_problems CP ON S.contest_id = CP.contest_id AND S.problem_id = CP.problem_id~,
        'name, text',
        { name => $p->{snippet_names}, 'CP.id' => $p->{cpid}, account_id => $account_id }));

    $_->{text} && $_->{text} =~ s/^(\s*)\$(.*)\$(\s*)$/$1 . CATS::TeX::Lite::convert_one($2) . $3/e
        for @$snippets;

    my $res = {};
    $res->{$_->{name}} = $_->{text} for @$snippets;

    return $p->print_json($res) if $p->{uid} && $is_jury;

    my ($contest_id, $problem_id) = $dbh->selectrow_array(q~
        SELECT contest_id, problem_id FROM contest_problems WHERE id = ?~, undef,
        $p->{cpid});

    my $snippet_names = $dbh->selectcol_arrayref(q~
        SELECT snippet_name FROM problem_snippets
        WHERE problem_id = ? AND snippet_name NOT IN
            (SELECT name FROM snippets
            WHERE contest_id = ? AND problem_id = ? AND account_id = ?) ~, undef,
        $problem_id, $contest_id, $problem_id, $uid);

    my @gen_snippets = grep !exists $res->{$_}, @$snippet_names;
    if (@gen_snippets) {
        for (@gen_snippets) {
            eval { $dbh->do(q~
                INSERT INTO snippets (id, name, contest_id, problem_id, account_id) VALUES (?, ?, ?, ?, ?)~, undef,
                new_id, $_, $contest_id, $problem_id, $uid);
            };
        }
        CATS::Job::create($cats::job_type_generate_snippets,
            { account_id => $uid, contest_id => $contest_id, problem_id => $problem_id });
        $dbh->commit;
    }

    $p->print_json($res);
}

sub snippets_frame {
    my ($p) = @_;

    $is_jury or return;

    init_template($p, 'snippets');
    $form->delete_or_saved($p);

    if ($p->{delete_sel} && @{$p->{sel}}) {
        my $count = $dbh->do(_u $sql->delete(
            'snippets', { id => $p->{sel}, $is_root ? () : (contest_id => $cid) }));
        $dbh->commit if $count;
        msg(1079, $count);
    }

    my $lv = CATS::ListView->new(web => $p, name => 'snippets', url => url_f('snippets'));

    $lv->default_sort(0)->define_columns([
        { caption => res_str(602), order_by => 'title', width => '20%' },
        { caption => res_str(608), order_by => 'team_name', width => '20%' },
        { caption => res_str(601), order_by => 'name', width => '20%' },
        { caption => res_str(672), order_by => 'text', width => '30%', col => 'Tx' },
        { caption => res_str(632), order_by => 'finish_time', width => '10%', col => 'Ft' },
    ]);

    $lv->define_db_searches([ qw(code name text team_name S.id cpid) ]);
    $lv->define_db_searches({
        # Disambiguate between snippets and contest_problems.
        problem_id => 'S.problem_id',
        contest_id => 'S.contest_id',
        account_id => 'S.account_id',
        text_len => 'COALESCE(CHARACTER_LENGTH(text), 0)',
        problem_title => 'P.title',
        contest_title => 'C.title',
    });
    $lv->default_searches([ qw(name text problem_title contest_title) ]);
    $lv->define_enums({ contest_id => { this => $cid } });

    my $finish_time = $lv->visible_cols->{Ft} ? qq~
        SELECT J.finish_time FROM jobs J
        WHERE J.contest_id = S.contest_id AND J.problem_id = S.problem_id AND
            J.account_id = S.account_id
        ORDER BY J.finish_time DESC $CATS::DB::db->{LIMIT} 1~ : 'NULL';

    my $text_prefix_len = 100;
    my $text_sql = $lv->visible_cols->{Tx} ? qq~
        SUBSTRING(CAST(S.text AS $CATS::DB::db->{BLOB_TYPE}) FROM 1 FOR $text_prefix_len) AS text,
        CASE WHEN CHARACTER_LENGTH(S.text) > $text_prefix_len THEN 1 ELSE 0 END AS text_overflow,
    ~ : '';

    my $sth = $dbh->prepare(qq~
        SELECT
            S.id, S.name, S.problem_id, S.account_id,
            P.title,
            CP.code,
            CP.id AS cpid,
            A.team_name,
            $text_sql
            ($finish_time) AS finish_time
        FROM snippets S
        INNER JOIN contests C ON C.id = S.contest_id
        INNER JOIN problems P ON P.id = S.problem_id
        LEFT JOIN contest_problems CP ON CP.problem_id = S.problem_id AND CP.contest_id = S.contest_id
        INNER JOIN accounts A ON A.id = S.account_id
        WHERE ~ . ($is_root ? '1 = 1 ' : 'S.contest_id = ? ') .
        $lv->maybe_where_cond . $lv->order_by
    );
    $sth->execute(($is_root ? () : $cid), $lv->where_params);


    my $fetch_record = sub {
        my $c = $_[0]->fetchrow_hashref or return ();
        return (
            %$c,
            text => Encode::decode_utf8($c->{text}, Encode::FB_QUIET),
            href_edit => url_f('snippets_edit', id => $c->{id}),
            href_delete => url_f('snippets', delete => $c->{id}),
            href_view => url_f('problem_text', uid => $c->{account_id}, cpid => $c->{cpid}),
            href_problem_snippets => url_f('problem_snippets', pid => $c->{problem_id}),
            href_user => url_f('user_stats', uid => $c->{account_id}),
        );
    };
    $lv->date_fields(qw(finish_time));
    $lv->attach($fetch_record, $sth);

    $sth->finish;

    _submenu;
}

1;
