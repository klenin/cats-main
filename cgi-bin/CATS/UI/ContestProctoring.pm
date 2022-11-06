package CATS::UI::ContestProctoring;

use strict;
use warnings;

use JSON::XS;

use CATS::Contest::Utils;
use CATS::DB;
use CATS::Globals qw($cid $is_root $t);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template);

sub contest_proctoring_frame {
    my ($p) = @_;
    init_template($p, 'contest_proctoring');
    $is_root or return;
    my ($id, $old_params) = $dbh->selectrow_array(q~
        SELECT contest_id, params FROM proctoring
        WHERE contest_id = ?~, undef,
        $cid);
    $t->param(
        params => ($p->{save} ? $p->{params} : $old_params),
    );
    CATS::Contest::Utils::contest_submenu('contest_proctoring');

    if ($p->{save} && ($p->{params} // '') ne ($old_params // '')) {
        eval { decode_json($p->{params}); 1 }
            or return msg(1236, $@);
        if ($p->{params}) {
             my @r = ('proctoring', { contest_id => $cid, params => $p->{params} });
             $dbh->do(_u $id ? $sql->update(@r) : $sql->insert(@r));
        }
        else {
            $dbh->do(q~
                DELETE FROM proctoring WHERE contest_id = ?~, undef,
                $cid);
        }
        $dbh->commit;
    }
}

1;
