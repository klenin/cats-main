package CATS::UI::Prizes;

use strict;
use warnings;

use CATS::Contest::Utils;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $t $uid);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;
use CATS::RouteParser;

sub contest_groups_fields () { qw(name clist) }

sub prizes_edit_frame {
    my ($p) = @_;
    init_template($p, 'prizes_edit.html.tt');

    my $cg = $dbh->selectrow_hashref(q~
        SELECT * FROM contest_groups WHERE id = ?~, undef,
        $p->{edit});
    my $prizes = $dbh->selectall_arrayref(q~
        SELECT * FROM prizes WHERE cg_id = ?~, { Slice => {} },
        $p->{edit});
    $t->param(%$cg, prizes => $prizes, href_action => url_f('prizes'));
}

sub pluck { map $_->{$_[0]}, @{$_[1]} }

sub prize_params {
    my ($p, $id) = @_;
    map { $_ => $p->{"$_-$id"} } qw(rank name);
}

sub prizes_edit_save {
    my ($p) = @_;
    my $cgid = $p->{id} or return;

    my @clist = sort { $a <=> $b } @{$p->{clist}};
    @clist && @clist < 100 or return;
    my $clist = join ',', @clist;

    return msg(1090) if $cgid != (CATS::Contest::Utils::contest_group_by_clist($clist) // 0);

    my $prizes = $dbh->selectall_arrayref(q~
        SELECT * FROM prizes WHERE cg_id = ?~, { Slice => {} },
        $cgid);
    CATS::RouteParser::parse_route($p, [ 1,
        map { +"rank-$_" => integer, "name-$_" => str } pluck(id => $prizes), 'new' ]) or return;

    $dbh->do(_u $sql->update('contest_groups',
        { name => $p->{name} // '', clist => $clist }, { id => $cgid }));
    for my $pr (@$prizes) {
        my %new = prize_params($p, $pr->{id});
        if (!$new{rank} || !$new{name}) {
            $dbh->do(_u $sql->delete('prizes', { id => $pr->{id} }));
        }
        elsif ($new{rank} != $pr->{rank} || $new{name} ne $pr->{name}) {
            $dbh->do(_u $sql->update('prizes', \%new, { id => $pr->{id} }));
        }
    }
    my %new = prize_params($p, 'new');
    if ($new{rank} && $new{name}) {
        $dbh->do(_u $sql->insert('prizes', {
            %new, id => \'gen_id(key_seq, 1)', cg_id => $cgid }));
    }
    $dbh->commit;
}

sub prizes_frame {
    my ($p) = @_;
    if ($is_root && $p->{'delete'}) {
        $dbh->do(q~
            DELETE FROM contest_groups WHERE id = ?~, undef,
            $p->{'delete'});
        $dbh->commit;
    }

    $is_root && $p->{edit} and return prizes_edit_frame($p);
    init_template($p, 'prizes.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'prizes', url => url_f('prizes'));

    $p->{edit_save} and prizes_edit_save($p);

    $lv->default_sort(0)->define_columns([
        { caption => res_str(601), order_by => '2', width => '30%' },
        { caption => res_str(645), order_by => '3', width => '30%' },
        { caption => res_str(646), order_by => '4', width => '40%' },
    ]);

    my $sth = $dbh->prepare(q~
        SELECT cg.id, cg.name, cg.clist,
            (SELECT LIST(rank || ':' || name, ' ') FROM prizes p WHERE p.cg_id = cg.id) AS prizes
            FROM contest_groups cg ~ . $lv->order_by);
    $sth->execute;

    my $fetch_record = sub {
        my $f = $_[0]->fetchrow_hashref or return ();
        (
            %$f,
            ($is_root ? (href_edit => url_f('prizes', edit => $f->{id})) : ()),
            ($is_root ? (href_delete => url_f('prizes', 'delete' => $f->{id})) : ()),
            href_rank_table => url_f('rank_table', clist => $f->{clist}, hide_ooc => 1, show_prizes => 1),
        );
    };

    $lv->attach($fetch_record, $sth);

    $t->param(submenu => [ CATS::References::menu('prizes') ]);
}

# TODO
sub contests_prizes_frame {
    my ($p) = @_;
    init_template($p, 'contests_prizes');

    my @clist = sort { $a <=> $b } @{$p->{clist}};
    @clist && @clist < 100 or return;
    my $clist = join ',', @clist;

    my $lv = CATS::ListView->new(
        web => $p, name => 'contests_prizes', url => url_f('contests_prizes', clist => $clist));
    my $cg = $dbh->selectall_arrayref(q~
        SELECT cg.id, cg.name, cg.clist FROM contest_groups cg WHERE clist = ?~, { Slice => {} },
        $clist) or return;
    $cg = $cg->[0] or return;

    $lv->default_sort(0)->define_columns([
        { caption => res_str(647), order_by => '2', width => '30%' },
        { caption => res_str(648), order_by => '3', width => '70%' },
    ]);

    my $sth = $dbh->prepare(q~
        SELECT p.id, p.rank, p.name FROM prizes p WHERE p.cg_id = ? ~ . $lv->order_by);
    $sth->execute($cg->{id});

    my $fetch_record = sub {
        my $f = $_[0]->fetchrow_hashref or return ();
        (
            %$f,
        );
    };

    $lv->attach($fetch_record, $sth);

    $t->param(cg => $cg);
    #$t->param(submenu => [ CATS::References::menu('prizes') ]);
}

1;
