package CATS::UI::Prizes;

use strict;
use warnings;

use CATS::Contest::Utils;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t $uid);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;
use CATS::Web qw(param url_param);

sub contest_groups_fields () { qw(name clist) }

sub sanitize_clist { sort { $a <=> $b } grep /^\d+$/, @_ }

sub prizes_edit_frame {
    my ($p) = @_;
    init_template($p, 'prizes_edit.html.tt');

    my $cgid = url_param('edit') or return;
    my $cg = $dbh->selectrow_hashref(q~
        SELECT * FROM contest_groups WHERE id = ?~, undef,
        $cgid);
    my $prizes = $dbh->selectall_arrayref(q~
        SELECT * FROM prizes WHERE cg_id = ?~, { Slice => {} },
        $cgid);
    $t->param(%$cg, prizes => $prizes, href_action => url_f('prizes'));
}

sub prize_params { map { $_ => param($_ . '_' . $_[0]) } qw(rank name) }

sub prizes_edit_save {
    my $cgid = param('id') or return;
    my %cg = map { $_ => (param($_) || '') } contest_groups_fields;

    my @clist = sanitize_clist split ',', $cg{clist};
    @clist && @clist < 100 or return;
    $cg{clist} = join ',', @clist;
    return msg(1090) if $cgid != (CATS::Contest::Utils::contest_group_by_clist($cg{clist}) // 0);

    $dbh->do(_u $sql->update('contest_groups', \%cg, { id => $cgid }));
    my $prizes = $dbh->selectall_arrayref(q~
        SELECT * FROM prizes WHERE cg_id = ?~, { Slice => {} },
        $cgid);
    for my $p (@$prizes) {
        my %new = prize_params($p->{id});
        if (!$new{rank} || !$new{name}) {
            $dbh->do(_u $sql->delete('prizes', { id => $p->{id} }));
        }
        elsif ($new{rank} != $p->{rank} || $new{name} ne $p->{name}) {
            $dbh->do(_u $sql->update('prizes', \%new, { id => $p->{id} }));
        }
    }
    my %new = prize_params('new');
    if ($new{rank} && $new{name}) {
        $dbh->do(_u $sql->insert('prizes', {
            %new, id => \'gen_id(key_seq, 1)', cg_id => $cgid }));
    }
    $dbh->commit;
}

sub prizes_frame {
    my ($p) = @_;
    if ($is_root && (my $cgid = url_param('delete'))) {
        $dbh->do(q~
            DELETE FROM contest_groups WHERE id = ?~, undef,
            $cgid);
        $dbh->commit;
    }

    $is_root && defined url_param('edit') and return prizes_edit_frame;
    init_template($p, 'prizes.html.tt');
    my $lv = CATS::ListView->new(name => 'prizes');

    defined param('edit_save') and prizes_edit_save;

    $lv->define_columns(url_f('prizes'), 0, 0, [
        { caption => res_str(601), order_by => '2', width => '30%' },
        { caption => res_str(645), order_by => '3', width => '30%' },
        { caption => res_str(646), order_by => '4', width => '40%' },
    ]);

    my $c = $dbh->prepare(q~
        SELECT cg.id, cg.name, cg.clist,
            (SELECT LIST(rank || ':' || name, ' ') FROM prizes p WHERE p.cg_id = cg.id) AS prizes
            FROM contest_groups cg ~ . $lv->order_by);
    $c->execute;

    my $fetch_record = sub {
        my $f = $_[0]->fetchrow_hashref or return ();
        (
            %$f,
            ($is_root ? (href_edit => url_f('prizes', edit => $f->{id})) : ()),
            ($is_root ? (href_delete => url_f('prizes', 'delete' => $f->{id})) : ()),
            href_rank_table => url_f('rank_table', clist => $f->{clist}, hide_ooc => 1, show_prizes => 1),
        );
    };

    $lv->attach(url_f('prizes'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('prizes') ]);
}

sub contests_prizes_frame {
    my ($p) = @_;
    init_template($p, 'contests_prizes');
    my $lv = CATS::ListView->new(name => 'contests_prizes');

    my @clist = sanitize_clist param('clist');
    @clist && @clist < 100 or return;
    my $clist = join ',', @clist;

    my $cg = $dbh->selectall_arrayref(q~
        SELECT cg.id, cg.name, cg.clist FROM contest_groups cg WHERE clist = ?~, { Slice => {} },
        $clist) or return;
    $cg = $cg->[0] or return;

    $lv->define_columns(url_f('contests_prizes', clist => $clist), 0, 0, [
        { caption => res_str(647), order_by => '2', width => '30%' },
        { caption => res_str(648), order_by => '3', width => '70%' },
    ]);

    my $c = $dbh->prepare(q~
        SELECT p.id, p.rank, p.name FROM prizes p WHERE p.cg_id = ? ~ . $lv->order_by);
    $c->execute($cg->{id});

    my $fetch_record = sub {
        my $f = $_[0]->fetchrow_hashref or return ();
        (
            %$f,
        );
    };

    $lv->attach(url_f('contests_prizes'), $fetch_record, $c);

    $t->param(cg => $cg);
    #$t->param(submenu => [ CATS::References::menu('prizes') ]);
}

1;
