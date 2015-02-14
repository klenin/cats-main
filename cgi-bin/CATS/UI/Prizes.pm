package CATS::UI::Prizes;

use strict;
use warnings;

use CATS::Web qw(param url_param);
use CATS::DB;
use CATS::Misc qw($t init_template msg url_f);


sub sanitize_clist { sort { $a <=> $b } grep /^\d+$/, @_ }


sub is_unique_contest_group
{
    $dbh->selectrow_array(q~
        SELECT id FROM contest_groups WHERE clist = ?~, undef,
        $_[0]) ? msg(90) : 1;
}


sub contest_group_auto_new
{
    my @clist = sanitize_clist param('contests_selection');
    @clist && @clist < 100 or return;
    my $clist = join ',', @clist;
    is_unique_contest_group($clist) or return;
    my $names = $dbh->selectcol_arrayref(_u
        $sql->select('contests', 'title', { id => \@clist })) or return;
    my $name = join ' ', @{(
        List::Util::reduce { CATS::RankTable::common_prefix($a, $b) }
        map [ split /\s+|_/, $_ ], @$names
    )};
    $dbh->do(q~
        INSERT INTO contest_groups (id, name, clist)
        VALUES (gen_id(key_seq, 1), ?, ?)~, undef,
        $name, $clist);
    $dbh->commit;
    msg(89, $name);
}


sub contest_groups_fields () { qw(name clist) }


sub prizes_edit_frame
{
    init_template('prizes_edit.html.tt');

    my $cgid = url_param('edit') or return;
    my $cg = $dbh->selectrow_hashref(qq~
        SELECT * FROM contest_groups WHERE id = ?~, undef, $cgid);
    my $prizes = $dbh->selectall_arrayref(qq~
        SELECT * FROM prizes WHERE cg_id = ?~, { Slice => {} }, $cgid);
    $t->param(%$cg, prizes => $prizes, href_action => url_f('prizes'));
}


sub prize_params { map { $_ => param($_ . '_' . $_[0]) } qw(rank name) }


sub prizes_edit_save
{
    my $cgid = param('id');
    my %cg = map { $_ => (param($_) || '') } contest_groups_fields;

    my @clist = sanitize_clist split ',', $cg{clist};
    @clist && @clist < 100 or return;
    $cg{clist} = join ',', @clist;
    is_unique_contest_group($cg{clist}) or return;

    $dbh->do(_u $sql->update('contest_groups', \%cg, { id => $cgid }));
    my $prizes = $dbh->selectall_arrayref(qq~
        SELECT * FROM prizes WHERE cg_id = ?~, { Slice => {} }, $cgid);
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


1;
