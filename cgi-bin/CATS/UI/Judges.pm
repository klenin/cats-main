package CATS::UI::Judges;

use strict;
use warnings;

use CATS::DB;
use CATS::DevEnv;
use CATS::Form;
use CATS::Globals qw($is_jury $is_root $t);
use CATS::IP;
use CATS::Job;
use CATS::Judge;
use CATS::JudgeDB;
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;

sub edit_frame {
    my ($p) = @_;
    init_template($p, 'judges_edit.html.tt');

    if (my $jid = $p->{edit}) {
        my ($judge_name, $account_name, $pin_mode, $account_id) = $dbh->selectrow_array(q~
            SELECT J.nick, A.login, J.pin_mode, J.account_id
            FROM judges J LEFT JOIN accounts A ON A.id = J.account_id WHERE J.id = ?~, undef,
            $jid);

        my $de_bitmap = CATS::DB::select_row('judge_de_bitmap_cache', '*', { judge_id => $jid });
        my $supported_DEs;
        if ($de_bitmap) {
            my $dev_env = CATS::DevEnv->new(CATS::JudgeDB::get_DEs);
            $supported_DEs = [ $dev_env->by_bitmap([ CATS::JudgeDB::extract_de_bitmap($de_bitmap) ]) ],
        }
        $t->param(
            href_contests => url_f('contests', search => "has_user($account_id)"),
            id => $jid, judge_name => $judge_name, account_name => $account_name, pin_mode => $pin_mode,
            de_bitmap => $de_bitmap, supported_DEs => $supported_DEs,
        );
    }
    $t->param(href_action => url_f('judges'));
}

sub edit_save {
    my ($p) = @_;
    my $judge_name = $p->{judge_name} // '';
    my $account_name = $p->{account_name} // '';
    my $pin_mode = $p->{pin_mode} // 0;

    $judge_name ne '' && length $judge_name <= 20
        or return msg(1005);

    my $account_id;
    if ($account_name) {
        $account_id = $dbh->selectrow_array(q~
            SELECT id FROM accounts WHERE login = ?~, undef,
            $account_name) or return msg(1139, $account_name);
    }

    if ($p->{id}) {
        $dbh->do(q~
            UPDATE judges SET nick = ?, account_id = ?, pin_mode = ? WHERE id = ?~, undef,
            $judge_name, $account_id, $pin_mode, $p->{id});
        $dbh->commit;
        msg(1140, $judge_name);
    }
    else {
        $dbh->do(q~
            INSERT INTO judges (id, nick, account_id, pin_mode, is_alive, alive_date)
            VALUES (?, ?, ?, ?, 0, CURRENT_TIMESTAMP)~, undef,
            new_id, $judge_name, $account_id, $pin_mode);
        $dbh->commit;
        msg(1006, $judge_name);
    }
}

my $form = CATS::Form->new({ table => 'judges', fields => [], });

sub update_judges {
    my ($p) = @_;

    my $count = 0;
    for my $judge_id (@{$p->{selected}}) {
        CATS::Job::create($cats::job_type_update_self, { judge_id => $judge_id }) and ++$count;
    }
    $count or return;
    $dbh->commit;
    msg(1171, $count);
}

sub set_pin_mode {
    my ($p) = @_;

    my $count = 0;
    my $sth = $dbh->prepare(q~
        UPDATE judges SET pin_mode = ? WHERE pin_mode <> ? AND id = ?~);
    $count += $sth->execute($p->{pin_mode}, $p->{pin_mode}, $_) for @{$p->{selected}};
    $count or return;
    $dbh->commit;
    msg(1172, $count);
}

sub judges_frame {
    my ($p) = @_;
    $is_jury or return;

    if ($is_root) {
        if ($p->{ping}) {
            CATS::Judge::ping($p->{ping});
            return $p->redirect(url_f 'judges');
        }
        $p->{new} || $p->{edit} and return edit_frame($p);
        $p->{update} and update_judges($p);
        $p->{set_pin_mode} && defined $p->{pin_mode} and set_pin_mode($p);
    }

    init_template($p, 'judges.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'judges');

    if ($is_root) {
        $p->{edit_save} and edit_save($p);
        $form->edit_delete(id => $p->{delete}, descr => 'nick', msg => 1020);
    }

    $lv->define_columns(url_f('judges'), 0, 0, [
        { caption => res_str(625), order_by => 'nick', width => '15%' },
        ($is_root ? ({ caption => res_str(616), order_by =>  'login', width => '25%', col => 'Lg' }) : ()),
        ($is_root ? ({ caption => res_str(649), order_by => 'processing_count', width => '10%', col => 'Rq' }) : ()),
        { caption => res_str(626), order_by => 'is_alive', width => '10%', col => 'Re' },
        { caption => res_str(633), order_by => 'alive_date', width => '10%', col => 'Ad' },
        { caption => res_str(622), order_by => 'pin_mode', width => '10%' },
        { caption => res_str(676), order_by => 'version', width => '15%', col => 'Vr' },
    ]);
    $lv->define_db_searches([ qw(J.id nick login version is_alive alive_date pin_mode account_id last_ip) ]);

    my $req_counts =
        !$is_root || !$lv->visible_cols->{Rq} ? ', NULL AS processing_count, NULL AS processed_count' :
        qq~,
        (SELECT COUNT(*) FROM reqs R WHERE R.judge_id = J.id AND R.state <= $cats::st_testing) AS processing_count,
        (SELECT COUNT(*) FROM reqs R WHERE R.judge_id = J.id) AS processed_count~;

    my $c = $dbh->prepare(qq~
        SELECT
            J.id AS jid, J.nick AS judge_name, A.login AS account_name,
            J.version, J.is_alive, J.alive_date, J.pin_mode,
            A.id AS account_id, A.last_ip, A.restrict_ips$req_counts
        FROM judges J LEFT JOIN accounts A ON A.id = J.account_id WHERE 1 = 1 ~ .
        $lv->maybe_where_cond . $lv->order_by);
    $c->execute($lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        my $jid = $row->{jid};
        return (
            %$row,
            CATS::IP::linkify_ip($row->{last_ip}),

            href_ping => url_f('judges', ping => $jid),
            href_edit => url_f('judges', edit => $jid),
            href_delete => url_f('judges', 'delete' => $jid),
            href_account => url_f('users_edit', uid => $row->{account_id}),
            href_console => url_f('console',
                search => "judge_id=$jid,state<=T", se => 'judge', i_value => -1, show_results => 1),
            href_update_jobs => url_f('jobs',
                search => "judge_id=$jid,type=$cats::job_type_update_self"),
        );
    };

    $lv->attach(url_f('judges'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('judges') ], editable => $is_root);

    my ($not_processed) = $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM reqs WHERE state = ? AND judge_id IS NULL~, undef,
        $cats::st_not_processed);
    $t->param(not_processed => $not_processed);
}

1;
