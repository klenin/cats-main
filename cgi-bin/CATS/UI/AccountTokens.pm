package CATS::UI::AccountTokens;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

sub account_tokens_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'account_tokens.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'account_tokens');

    #$is_root and $form->delete_or_saved($p);
    if ($p->{delete}) {
        $dbh->do(q~
            DELETE FROM account_tokens WHERE token = ?~, undef,
            $p->{delete}) and msg(1186, $p->{delete});
        $dbh->commit;
    }

    $lv->define_columns(url_f('account_tokens'), 0, 0, [
        { caption => res_str(619), order_by => 'token', width => '30%' },
        { caption => res_str(608), order_by => 'account_id', width => '30%' },
        { caption => res_str(683), order_by => 'usages_left', width => '10%', col => 'Ul' },
        { caption => res_str(632), order_by => 'last_used', width => '10%', col => 'Lu' },
        { caption => res_str(668), order_by => 'referer', width => '30%', col => 'Rf' },
    ]);

    #$lv->define_db_searches($form->{sql_fields});

    my ($q, @bind) = $sql->select('account_tokens AcT INNER JOIN accounts A ON AcT.account_id = A.id',
        [ qw(AcT.token AcT.account_id AcT.usages_left AcT.last_used AcT.referer A.team_name) ],
        $lv->where);
    my $c = $dbh->prepare("$q " . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_user => url_f('users_edit', uid => $row->{account_id}),
            ($is_root ? (
                #href_edit => url_f('account_tokens', id => $row->{did}),
                href_delete => url_f('account_tokens', 'delete' => $row->{token})) : ()),
        );
    };
    $lv->attach(url_f('account_tokens'), $fetch_record, $c);
    $t->param(submenu => [ CATS::References::menu('account_tokens') ]);
}

1;
