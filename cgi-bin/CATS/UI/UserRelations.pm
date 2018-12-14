package CATS::UI::UserRelations;

use strict;
use warnings;

use Encode;
use List::Util qw(max min);

use CATS::DB;
use CATS::Form;
use CATS::Globals qw ($cid $is_root $t $user);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::User;

sub _check {
    my ($fd, $p) = @_;

    my $from_id = $fd->{indexed}->{from_id}->{value} || 0;
    my $to_id = $fd->{indexed}->{to_id}->{value} || 0;
    $from_id != $to_id or return msg(1179);

    return 1 if $is_root;

    ($from_id == $user->{id} || $to_id == $user->{id}) or return msg(1181);

    my $old;
    if ($fd->{id}) {
        $old = $dbh->selectrow_hashref(q~
            SELECT from_id, to_id, from_ok, to_ok FROM relations WHERE id = ?~, { Slice => {} },
            $fd->{id});
        ($old->{from_id} == $user->{id} || $old->{to_id} == $user->{id}) &&
        (!$old->{from_ok} || $from_id == $old->{from_id}) &&
        (!$old->{to_ok} || $to_id == $old->{to_id})
            or return msg(1178);
    }

    if ($from_id == $user->{id}) {
        my $to_ok = $fd->{indexed}->{to_ok};
        if (($to_ok->{value} || 0) != ($old->{to_ok} // 0)) {
            $to_ok->{error} = res_str(1180);
            return;
        }
    }
    if ($to_id == $user->{id}) {
        my $from_ok = $fd->{indexed}->{from_ok};
        if (($from_ok->{value} || 0) != ($old->{from_ok} // 0)) {
            $from_ok->{error} = res_str(1180);
            return;
        }
    }
    1;
}

my @rel_values = values %$CATS::Globals::relation;

sub _parse_login {
    my ($value, $p, $login) = @_;
    return $value if $p->{js};
    $dbh->selectrow_array(q~
        SELECT id FROM accounts WHERE login = ?~, undef,
        $p->{$login} // '') // 0;
}

our $form = CATS::Form->new(
    table => 'relations',
    fields => [
        [ name => 'rel_type', validators => [
            CATS::Field::int_range(min => min(@rel_values), max => max(@rel_values)) ], caption => 642, ],
        [ name => 'from_id', after_parse => sub { _parse_login(@_, 'from_login') },
            validators => [ $CATS::Fields::foreign_key ], caption => 679 ],
        [ name => 'to_id', after_parse => sub { _parse_login(@_, 'to_login') },
            validators => [ $CATS::Fields::foreign_key ], caption => 680, ],
        [ name => 'from_ok', validators => [ $CATS::Field::bool ], caption => 622, ],
        [ name => 'to_ok', validators => [ $CATS::Field::bool ], caption => 622, ],
        [ name => 'ts', before_save => sub { \'CURRENT_TIMESTAMP' } ],
    ],
    href_action => 'user_relations_edit',
    descr_field => 'id',
    template_var => 'ur',
    msg_deleted => 1177,
    msg_saved => 1176,
    before_delete => sub {
        my ($p, $id) = @_;
        $is_root || $dbh->selectrow_array(q~
            SELECT id FROM relations WHERE id = ? AND (from_id = ? OR to_id = ?)~, undef,
            $id, $user->{id}, $user->{id});
    },
    before_display => sub {
        my ($fd, $p) = @_;
        $fd->{accounts} = $fd->{id} ? $dbh->selectall_hashref(q~
            SELECT A.id, A.team_name, A.login
            FROM accounts A
            WHERE A.id = ? OR A.id = ?~, 'id', { Slice => {} },
            $fd->{indexed}->{from_id}->{value},
            $fd->{indexed}->{to_id}->{value}) : {};
        $fd->{rel_types} = [
            sort { $a->{value} <=> $b->{value} }
            map { value => $CATS::Globals::relation->{$_}, text => $_ },
            keys %$CATS::Globals::relation ];
        $fd->{href_find_users} = url_f('api_find_users');
        $t->param(CATS::User::submenu('user_relations', $p->{uid}));
    },
    validators => [ \&_check ],
);

sub user_relations_edit_frame {
    my ($p) = @_;
    init_template($p, 'user_relations_edit.html.tt');
    $is_root || ($user->{id} // 0) == $p->{uid} or return;
    my @puid = (uid => $p->{uid});
    $form->edit_frame($p, redirect => [ 'user_relations', @puid ], href_action_params => \@puid);
}

my $_contest_account_sql = q~
    SELECT 1 FROM contest_accounts CA
    WHERE CA.contest_id = ? AND CA.account_id = A.id~;
sub find_users_api {
    my ($p) = @_;
    my $root_cond = $is_root ? '' : ' AND srole > 0';
    my $contest_cond =
        !exists $p->{in_contest} ? '' :
        $p->{in_contest} > 0 ?
            " AND EXISTS ($_contest_account_sql)" :
            " AND NOT EXISTS ($_contest_account_sql)";
    my $r = $dbh->selectall_arrayref(qq~
        SELECT A.id, A.login, A.team_name FROM accounts A
        WHERE (A.login STARTS WITH ? OR A.team_name STARTS WITH ?)$root_cond$contest_cond
        ORDER BY A.login
        ROWS 100~,
        { Slice => {} },
        $p->{query}, $p->{query}, ($contest_cond ? $p->{in_contest} : ()));
    $p->print_json({ suggestions =>
        [ map { value => $_->{login}, data => $_ }, @$r ]
    });
}

sub _url_accept {
    my ($row, @rest) = @_;
    url_f('user_relations_edit', uid => $user->{id},
        (map { $_ => $row->{$_} } qw(id rel_type from_id to_id)),
        js => 1, edit_save => 1, @rest);
}

sub user_relations_frame {
    my ($p) = @_;

    init_template($p, 'user_relations.html.tt');
    $is_root || ($user->{id} // 0) == $p->{uid} or return;

    $form->delete_or_saved($p);

    my $lv = CATS::ListView->new(web => $p, name => 'user_relations');
    my ($user_name) = $dbh->selectrow_array(q~
        SELECT team_name FROM accounts WHERE id = ?~, undef,
        $p->{uid}) or return;

    $lv->define_columns(url_f('user_relations'), 0, 0, [
        { caption => res_str(679), order_by => 'from_name', width => '30%' },
        { caption => res_str(642), order_by => 'rel_type', width => '20%' },
        { caption => res_str(680), order_by => 'to_name', width => '30%' },
        { caption => res_str(632), order_by => 'ts', width => '20%', col => 'Ts' },
    ]);
    $lv->define_db_searches($form->{sql_fields});
    my $sth = $dbh->prepare(qq~
        SELECT R.id, R.rel_type, R.from_id, R.to_id, R.from_ok, R.to_ok, R.ts,
          (SELECT A.team_name FROM accounts A WHERE A.id = R.from_id) AS from_name,
          (SELECT A.team_name FROM accounts A WHERE A.id = R.to_id) AS to_name
        FROM relations R
        WHERE R.from_id = ? OR R.to_id = ?~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($p->{uid}, $p->{uid}, $lv->where_params);

    my @pp = (uid => $p->{uid});
    my $user_page = $is_root ? 'users_edit' : 'user_stats';
    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        (
            %$row,
            type_name => $CATS::Globals::relation_to_name->{$row->{rel_type}},
            href_edit => url_f('user_relations_edit', id => $row->{id}, @pp),
            href_delete => url_f('user_relations', 'delete' => $row->{id}, @pp),
            href_from => url_f($user_page, uid => $row->{from_id}),
            href_to => url_f($user_page, uid => $row->{to_id}),
            href_from_accept => $row->{from_id} == $user->{id} && !$row->{from_ok} ?
                _url_accept($row, from_ok => 1, to_ok => $row->{to_ok}) : undef,
            href_to_accept => $row->{to_id} == $user->{id} && !$row->{to_ok} ?
                _url_accept($row, from_ok => $row->{from_ok}, to_ok => 1) : undef,
        );
    };
    $lv->attach(url_f('user_relations'), $fetch_record, $sth, { page_params => { @pp } });
    $t->param(
        CATS::User::submenu('user_relations', $p->{uid}),
        title_suffix => res_str(597),
        problem_title => $user_name,
    );
}

1;
