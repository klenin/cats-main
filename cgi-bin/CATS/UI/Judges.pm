package CATS::UI::Judges;

use strict;
use warnings;

use CATS::Web qw(param param_on url_param redirect);
use CATS::DB;
use CATS::Misc qw(
    $t $is_jury $is_root
    init_template init_listview_template msg res_str url_f
    order_by define_columns attach_listview references_menu);

use CATS::Judge;

sub edit_frame
{
    init_template('judges_edit.html.tt');

    if (my $jid = url_param('edit')) {
        my ($judge_name, $account_name, $lock_counter) = $dbh->selectrow_array(q~
            SELECT J.nick, A.login, J.lock_counter
            FROM judges J LEFT JOIN accounts A ON A.id = J.account_id WHERE J.id = ?~, undef,
            $jid);
        $t->param(id => $jid, judge_name => $judge_name, account_name => $account_name, locked => $lock_counter);
    }
    $t->param(href_action => url_f('judges'));
}

sub edit_save
{
    my $jid = param('id');
    my $judge_name = param('judge_name') // '';
    my $account_name = param('account_name') // '';
    my $locked = param_on('locked') ? -1 : 0;

    $judge_name ne '' && length $judge_name <= 20
        or return msg(1005);

    my $account_id;
    if ($account_name) {
        $account_id = $dbh->selectrow_array(q~
            SELECT id FROM accounts WHERE login = ?~, undef,
            $account_name) or return msg(1139, $account_name);
    }

    if ($jid) {
        $dbh->do(q~
            UPDATE judges SET nick = ?, account_id = ?, lock_counter = ? WHERE id = ?~, undef,
            $judge_name, $account_id, $locked, $jid);
        $dbh->commit;
        msg(1140, $judge_name);
    }
    else {
        $dbh->do(q~
            INSERT INTO judges (id, nick, account_id, lock_counter, is_alive, alive_date)
            VALUES (?, ?, ?, ?, 0, CURRENT_TIMESTAMP)~, undef,
            new_id, $judge_name, $account_id, $locked);
        $dbh->commit;
        msg(1006, $judge_name);
    }
}

sub judges_frame
{
    $is_jury or return;

    if ($is_root) {
        if (my $jid = param('ping')) {
            CATS::Judge::ping($jid);
            return redirect(url_f('judges'));
        }
        defined url_param('new') || defined url_param('edit') and return edit_frame;
    }

    init_listview_template('judges', 'judges', 'judges.html.tt');

    if ($is_root) {
        defined param('edit_save') and edit_save;
        if (my $jid = url_param('delete')) {
            my $judge_name = $dbh->selectrow_array(q~
                SELECT nick FROM judges WHERE id = ?~, undef,
                $jid);
            if ($judge_name) {
                $dbh->do(q~
                    DELETE FROM judges WHERE id = ?~, undef,
                    $jid);
                $dbh->commit;
                msg(1020, $judge_name);
            }
        }
    }

    define_columns(url_f('judges'), 0, 0, [
        { caption => res_str(625), order_by => '2', width => '30%' },
        ($is_root ? ({ caption => res_str(616), order_by => '3', width => '30%' }) : ()),
        { caption => res_str(626), order_by => '4', width => '10%' },
        { caption => res_str(633), order_by => '5', width => '15%' },
        { caption => res_str(622), order_by => '6', width => '10%' },
    ]);

    my $c = $dbh->prepare(q~
        SELECT J.id, J.nick, A.login, J.is_alive, J.alive_date, J.lock_counter, A.id, A.last_ip
            FROM judges J LEFT JOIN accounts A ON A.id = J.account_id ~ . order_by);
    $c->execute;

    my $fetch_record = sub($)
    {
        my (
            $jid, $judge_name, $account_name, $is_alive, $alive_date, $lock_counter, $account_id, $last_ip
        ) = $_[0]->fetchrow_array or return ();
        return (
            editable => $is_root,
            jid => $jid,
            judge_name => $judge_name,
            account_name => $account_name,
            last_ip => $last_ip,
            locked => $lock_counter,
            is_alive => $is_alive,
            alive_date => $alive_date,
            href_ping => url_f('judges', ping => $jid),
            href_edit => url_f('judges', edit => $jid),
            href_delete => url_f('judges', 'delete' => $jid),
            href_account => url_f('users', edit => $account_id),
        );
    };

    attach_listview(url_f('judges'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('judges') ], editable => 1);

    my ($not_processed) = $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM reqs WHERE state = ?~, undef,
        $cats::st_not_processed);
    $t->param(not_processed => $not_processed);
}

1;
