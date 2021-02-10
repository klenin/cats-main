package CATS::UI::AccGroups;

use strict;
use warnings;

use CATS::Contest::Utils;
use CATS::DB;
use CATS::Form;
use CATS::Globals qw($cid $is_jury $is_root $t $uid);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;
use CATS::User;

our $form = CATS::Form->new(
    table => 'acc_groups',
    fields => [
        [ name => 'name',
            validators => [ CATS::Field::str_length(1, 200) ], editor => { size => 50 }, caption => 601 ],
        [ name => 'is_actual', validators => $CATS::Field::bool, caption => 670 ],
        [ name => 'description', caption => 620 ],
    ],
    href_action => 'acc_groups_edit',
    descr_field => 'name',
    template_var => 'ag',
    msg_saved => 1215,
    msg_deleted => 1216,
    before_display => sub { $t->param(submenu => [ CATS::References::menu('acc_groups') ]) },
);

sub acc_groups_edit_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'acc_groups_edit.html.tt');
    $form->edit_frame($p, redirect => [ 'acc_groups' ]);
}

sub acc_groups_frame {
    my ($p) = @_;

    $is_jury or return;
    $form->delete_or_saved($p) if $is_root;
    init_template($p, 'acc_groups');
    my $lv = CATS::ListView->new(web => $p, name => 'acc_groups', url => url_f('acc_groups'));

    CATS::Contest::Utils::add_remove_groups($p) if $p->{add} || $p->{remove};

    $lv->default_sort(0)->define_columns([
        { caption => res_str(601), order_by => 'name', width => '30%' },
        { caption => res_str(620), order_by => 'description', width => '30%', col => 'Ds' },
        { caption => res_str(685), order_by => 'is_used', width => '5%' },
        { caption => res_str(670), order_by => 'is_actual', width => '5%', col => 'Ac' },
        { caption => res_str(606), order_by => 'user_count', width => '5%', col => 'Uc' },
        { caption => res_str(643), order_by => 'ref_count', width => '5%', col => 'Rc' },
    ]);
    $lv->define_db_searches([ qw(id name is_actual description) ]);
    $lv->define_subqueries({
        in_contest => { sq => qq~EXISTS (
            SELECT 1 FROM acc_group_contests AGC
            WHERE AGC.contest_id = ? AND AGC.acc_group_id = AG.id)~,
            m => 1217, t => q~
            SELECT C.title FROM contests C WHERE C.id = ?~
        },
    });
    $lv->define_enums({ in_contest => { this => $cid } });

    my $user_count_sql = $lv->visible_cols->{Uc} ? q~
        SELECT COUNT(*) FROM acc_group_accounts AGA1 WHERE AGA1.acc_group_id = AG.id~ : 'NULL';
    my $ref_count_sql = $lv->visible_cols->{Rc} ? q~
        SELECT COUNT(*) FROM acc_group_contests AGC2 WHERE AGC2.acc_group_id = AG.id~ : 'NULL';
    my $descr_sql = $lv->visible_cols->{Ds} ? 'AG.description' : 'NULL';
    my $sth = $dbh->prepare(qq~
        SELECT AG.id, AG.name, AG.is_actual,
            (SELECT 1 FROM acc_group_contests AGC1
                WHERE AGC1.acc_group_id = AG.id AND AGC1.contest_id = ?) AS is_used,
            ($descr_sql) AS description,
            ($user_count_sql) AS user_count,
            ($ref_count_sql) AS ref_count
        FROM acc_groups AG WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $descr_prefix_len = 50;
    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            descr_prefix => substr($row->{description}, 0, $descr_prefix_len),
            descr_cut => length($row->{description}) > $descr_prefix_len,
            href_edit=> url_f('acc_groups_edit', id => $row->{id}),
            href_delete => url_f('acc_groups', 'delete' => $row->{id}),
            href_view_users => url_f('acc_group_users', group => $row->{id}),
            href_view_users_in_contest => url_f('users', search => "in_group($row->{id})"),
            href_view_contests => url_f('contests', search => "has_group($row->{id})"),
            href_rank_table => url_f('rank_table', groups => $row->{id}, 'sort' => 'name'),
        );
    };

    $lv->attach($fetch_record, $sth);

    $t->param(submenu => [ CATS::References::menu('acc_groups') ], editable => $is_root);
}

sub _set_field {
    my ($p, $field) = @_;
    my $set_sth = $dbh->prepare(qq~
        UPDATE acc_group_accounts SET $field = ?
        WHERE $field <> ? AND acc_group_id = ? AND account_id = ?~);
    my $value = $p->{$field} ? 1 : 0;
    my $count = 0;
    for (@{$p->{user_selection}}) {
        $count += $set_sth->execute($value, $value, $p->{group}, $_);
    }
    $dbh->commit if $count;
    msg(1018, $count);
}

sub acc_group_users_frame {
    my ($p) = @_;
    init_template($p, 'acc_group_users');
    $is_root && $p->{group} or return;

    my $group_name = $dbh->selectrow_array(q~
        SELECT name FROM acc_groups WHERE id = ?~, undef,
        $p->{group}) or return;

    _set_field($p, 'is_admin') if $p->{set_admin};
    _set_field($p, 'is_hidden') if $p->{set_hidden};

    if ($p->{delete_user}) {
        my $user_name = $dbh->selectrow_array(q~
            SELECT A.team_name
            FROM accounts A INNER JOIN acc_group_accounts AGA ON A.id = AGA.account_id
            WHERE AGA.account_id = ? AND AGA.acc_group_id = ?~, undef,
            $p->{delete_user}, $p->{group}) or return;
        $dbh->do(q~
            DELETE FROM acc_group_accounts
            WHERE account_id = ? AND acc_group_id = ?~, undef,
            $p->{delete_user}, $p->{group}) or die;
        $dbh->commit;
        msg(1094, $user_name);
    }

    my $lv = CATS::ListView->new(
        web => $p, name => 'acc_group_users', url => url_f('acc_group_users', group => $p->{group}));

    $lv->default_sort($is_root ? 1 : 0)->define_columns([
        ($is_root ?
            { caption => res_str(616), order_by => 'login', width => '20%' } : ()),
        { caption => res_str(608), order_by => 'team_name', width => '30%', checkbox => $is_root && '[name=sel]' },
        { caption => res_str(685), order_by => 'in_contest', width => '5%' },
        ($is_root ? (
            { caption => res_str(615), order_by => 'is_admin', width => '5%' },
            { caption => res_str(614), order_by => 'is_hidden', width => '5%' },
        ) : ()),
        { caption => res_str(600), order_by => 'date_start', width => '5%', col => 'Ds' },
        { caption => res_str(631), order_by => 'date_finish', width => '5%', col => 'Df' },
    ]);
    $lv->define_db_searches([ qw(login team_name account_id is_admin is_hidden) ]);
    $lv->define_db_searches({ id => 'account_id' });

    my $sth = $dbh->prepare(q~
        SELECT A.login, A.team_name,
            AGA.account_id, AGA.is_admin, AGA.is_hidden, AGA.date_start, AGA.date_finish,
            (SELECT 1 FROM contest_accounts CA
                WHERE CA.contest_id = ? AND CA.account_id = AGA.account_id) AS in_contest
        FROM acc_group_accounts AGA
        INNER JOIN accounts A ON A.id = AGA.account_id
        WHERE AGA.acc_group_id = ?~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $p->{group}, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            href_delete => url_f('acc_group_users', group => $p->{group}, delete_user => $row->{account_id}),
            href_edit => url_f('users_edit', uid => $row->{account_id}),
            href_stats => url_f('user_stats', uid => $row->{account_id}),
            %$row,
         );
    };
    $lv->date_fields(qw(date_start date_finish));

    $lv->attach($fetch_record, $sth);
    $sth->finish;
    $t->param(
        problem_title => $group_name,
        submenu => [
            { href => url_f('users_new', group => $p->{group}), item => res_str(541), new => 1 },
            { href => url_f('acc_group_add_users', group => $p->{group}), item => res_str(584) },
            { href => url_f('acc_groups'), item => res_str(410) },
        ],
    );
}

sub _add_accounts {
    my ($accounts, $group_id, $make_hidden) = @_;
    my $in_group_sth = $dbh->prepare(q~
        SELECT 1 FROM acc_group_accounts WHERE acc_group_id = ? AND account_id = ?~);
    my $add_sth = $dbh->prepare(q~
        INSERT INTO acc_group_accounts (acc_group_id, account_id, is_hidden, date_start)
        VALUES (?, ?, ?, CURRENT_DATE)~);
    my @new_accounts;
    for (@$accounts) {
        $in_group_sth->execute($group_id, $_);
        my ($in_group) = $in_group_sth->fetchrow_array;
        $in_group_sth->finish;
        $in_group ? msg(1120, $_) : push @new_accounts, $_;
    }
    for (@new_accounts) {
        $add_sth->execute($group_id, $_, $make_hidden ? 1 : 0);
    }
    $dbh->commit;
    \@new_accounts;
}

sub trim { s/^\s+|\s+$//; $_; }

sub _accounts_by_login {
    my ($login_str) = @_;
    $login_str = Encode::decode_utf8($login_str || '');
    my @logins = map trim, split(/,/, $login_str) or return msg(1101);
    my %aids;
    my $aid_sth = $dbh->prepare(q~
        SELECT id FROM accounts WHERE login = ?~);
    for (@logins) {
        length $_ <= 50 or return msg(1101);
        $aid_sth->execute($_);
        my ($aid) = $aid_sth->fetchrow_array;
        $aid_sth->finish;
        $aid or return msg(1118, $_);
        $aids{$aid} = 1;
    }
    %aids or return msg(1118);
    [ keys %aids ];
}

sub _accounts_by_contest {
    my ($contest_id, $include_ooc) = @_;
    $dbh->selectrow_array(_u $sql->select('contest_accounts', '1',
        { contest_id => $contest_id, account_id => $uid, is_jury => 1 })) or return;
    $dbh->selectcol_arrayref(_u $sql->select('contest_accounts', 'account_id',
        { contest_id => $contest_id, is_hidden => 0, is_jury => 0, $include_ooc ? () : (is_ooc => 0) }
    ));
}

sub _accounts_by_acc_group {
    my ($group_id, $include_admins) = @_;
    $dbh->selectcol_arrayref(_u $sql->select('acc_group_accounts', 'account_id',
        { acc_group_id => $group_id, $include_admins ? () : (is_admin => 0) }
    ));
}

sub acc_group_add_users_frame {
    my ($p) = @_;
    $is_root && $p->{group} or return;
    init_template($p, 'acc_group_add_users.html.tt');
    my $group_name = $dbh->selectrow_array(q~
        SELECT name FROM acc_groups WHERE id = ?~, undef,
        $p->{group}) or return;
    my $accounts =
        $p->{by_login} ? _accounts_by_login($p->{logins_to_add}) :
        $p->{source_cid} ? _accounts_by_contest($p->{source_cid}, $p->{include_ooc}) :
        $p->{source_group_id} ? _accounts_by_acc_group($p->{source_group_id}, $p->{include_admins}) :
        undef;
    $accounts = $accounts && _add_accounts($accounts, $p->{group}, $p->{make_hidden}) // [];
    msg(1221, scalar @$accounts) if @$accounts;

    my @url_p = ('acc_group_users', group => $p->{group});
    if ($p->{by_login}) {
        $t->param(CATS::User::logins_maybe_added($p, \@url_p, $accounts));
    }
    $t->param(
        href_action => url_f(acc_group_add_users => group => $p->{group}),
        problem_title => $group_name,
        title_suffix => res_str(584),
        href_find_users => url_f('api_find_users', in_contest => 0),
        href_find_contests => url_f('api_find_contests'),
        href_find_acc_groups => url_f('api_find_acc_groups'),
        submenu => [
            { href => url_f('acc_groups'), item => res_str(410) },
            { href => url_f(@url_p), item => res_str(526) },
        ],
    );
}

sub find_acc_groups_api {
    my ($p) = @_;
    my $acc_groups = $dbh->selectall_arrayref(qq~
        SELECT AG.id, AG.name FROM acc_groups AG
        WHERE POSITION(? IN AG.name) > 0 AND AG.is_actual = 1
        ORDER BY AG.name
        $CATS::DB::db->{LIMIT} 100~, { Slice => {} },
        $p->{query});
    $p->print_json({ suggestions =>
        [ map { value => $_->{name}, data => $_ }, @$acc_groups ]
    });
}

1;
