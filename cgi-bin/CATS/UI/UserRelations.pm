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

sub _check_owner {
    my ($fd, $p) = @_;
    return 1 if $is_root;

    my $from_id = $fd->{indexed}->{from_id};
    my $to_id = $fd->{indexed}->{to_id};

    if (!$fd->{id}) {
        $from_id->{value} = $p->{uid};
    }
    else {
        my ($old_from_id, $old_to_id) = $dbh->selectrow_array(q~
            SELECT from_id, to_id FROM relations WHERE id = ?~, undef,
            $fd->{id});
        $old_from_id == $user->{id} || $old_to_id == $user->{id}
            or return CATS::Messages::msg_debug('Bad account %d', $old_from_id);
    }
    1;
}

my $int_fk = CATS::Field::int_range(min => 1, max => 1000000000);
my @rel_values = values %$CATS::Globals::relation;

our $form = CATS::Form->new(
    table => 'relations',
    fields => [
        [ name => 'rel_type', validators => [
            CATS::Field::int_range(min => min(@rel_values), max => max(@rel_values)) ], caption => 642, ],
        [ name => 'from_id', validators => [ $int_fk ], caption => 679 ],
        [ name => 'to_id', validators => [ $int_fk ], caption => 680, ],
        [ name => 'from_ok', validators => [ CATS::Field::int_range(min => 0, max => 1, allow_empty => 1) ], caption => 622, ],
        [ name => 'to_ok', validators => [ CATS::Field::int_range(min => 0, max => 1, allow_empty => 1) ], caption => 622, ],
        [ name => 'ts', before_save => sub { \'CURRENT_TIMESTAMP' } ],
    ],
    href_action => 'user_relations_edit',
    descr_field => 'id',
    template_var => 'ur',
    msg_deleted => 1177,
    msg_saved => 1176,
    before_display => sub {
        my ($fd, $p) = @_;
        $fd->{accounts} = $dbh->selectall_arrayref(q~
            SELECT A.id AS "value", A.team_name || ' ' || A.login AS "text"
            FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id
            WHERE CA.contest_id = ? ORDER BY A.login~, { Slice => {} },
            $cid);
        $fd->{rel_types} = [
            sort { $a->{value} <=> $b->{value} }
            map { value => $CATS::Globals::relation->{$_}, text => $_ },
            keys %$CATS::Globals::relation ];
        $t->param(CATS::User::submenu('user_relations', $p->{uid}));
    },
    validators => [ \&_check_owner ],
);

sub user_relations_edit_frame {
    my ($p) = @_;
    init_template($p, 'user_relations_edit.html.tt');
    $is_root or return;
    my @puid = (uid => $p->{uid});
    $form->edit_frame($p, redirect => [ 'user_relations', @puid ], href_action_params => \@puid);
}

sub user_relations_frame {
    my ($p) = @_;

    init_template($p, 'user_relations.html.tt');
    $p->{uid} or return;

    my $editable = $is_root;
    $form->delete_or_saved($p) if $editable;

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
    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        (
            ($editable ? (
                href_edit => url_f('user_relations_edit', id => $row->{id}, @pp),
                href_delete => url_f('user_relations', 'delete' => $row->{id}, @pp),
                href_from => url_f('users_edit', uid => $row->{from_id}),
                href_to => url_f('users_edit', uid => $row->{to_id}),
            ) : ()),
            %$row,
            type_name => $CATS::Globals::relation_to_name->{$row->{rel_type}},
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
