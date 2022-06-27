package CATS::UI::Leaderboard;

use strict;
use warnings;

use CATS::DB qw(:DEFAULT $db);
use CATS::Globals qw($cid $is_jury $t);
use CATS::Output qw(init_template url_f url_f_cid);

sub get_tables_by_tag {
	my $tag = 'tournament';
	my $tagged_ids = $dbh->selectall_arrayref(q~
            SELECT id
            FROM reqs
            WHERE tag = ? AND elements_count > ?~, { Slice => {} },
            $tag, 1);
     return @$tagged_ids;
}

sub _group_table {
    my ($req_id) = @_;
    my $root_req = $dbh->selectrow_hashref(q~
        SELECT id, elements_count FROM reqs
        WHERE id = ? AND contest_id = ?~, undef,
        $req_id, $cid) or return;
        
    my $children = $dbh->selectcol_arrayref(q~
    	SELECT element_id FROM req_groups
    	WHERE group_id = ?~, undef,
    	$req_id);
    
    #my $children = $dbh->selectcol_arrayref(q~
    #    SELECT RG.element_id FROM req_groups RG
    #    INNER JOIN reqs R on R.id = RG.group_id
    #    WHERE R.tag = ?~, undef,
    #    "tournament");
    my (@teams, %tests);
    for my $c (@$children) {
        my $orig_team = $dbh->selectrow_array(q~
            SELECT A.team_name FROM accounts A
            INNER JOIN reqs R ON R.account_id = A.id
            INNER JOIN req_groups RG ON RG.element_id = R.id
            WHERE R.id = ?~, undef,
            $c);
         my $team_id = $dbh->selectrow_array(q~
            SELECT A.id FROM accounts A
            INNER JOIN reqs R ON R.account_id = A.id
            INNER JOIN req_groups RG ON RG.element_id = R.id
            WHERE R.id = ?~, undef,
            $c);
         my $details = $dbh->selectall_arrayref(q~
            SELECT test_rank, points
            FROM req_details
            WHERE req_id = ?~, { Slice => {} },
            $c);
         my $points_idx = {};
         my $total = 0;
         for (@$details) {
             $tests{$_->{test_rank}} = 1;
             $points_idx->{$_->{test_rank}} = $_->{points};
             $total += $_->{points} || 0;
         }
         push @teams, { name => $orig_team, id => $team_id, details => $points_idx, total => $total};
    }
    {
        tests => [ sort { $a <=> $b } keys %tests ],
        teams => [ sort { $b->{total} <=> $a->{total} } @teams ],
    }
}

sub leaderboard_frame {
   	my ($p) = @_;
    init_template($p, 'leaderboard');
    $is_jury or return;
    @{$p->{req_ids}} or return;
    if ($p->{req_ids}[0] == "tag") {
    	my @tagged_ids = get_tables_by_tag;
    	my @tagged_ids_array;
    	for (@tagged_ids) {
    		push(@tagged_ids_array, $_->{id});
    	}
    	$t->param(groups => [ map _group_table($_), @tagged_ids_array ], href_user_stats => url_f('user_stats'), debug_var => $debug_var);
    } else {
    	$t->param(groups => [ map _group_table($_), @{$p->{req_ids}} ], href_user_stats => url_f('user_stats'));
    }
}

1;
