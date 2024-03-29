package CATS::UI::Integrations;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $t);
use CATS::Output qw(init_template url_f);
use CATS::User;
use CATS::Utils;

sub integration_bkd_start_api {
    my ($p) = @_;
    $is_jury or return;
    $p->{$_} || return $p->print_json({ error => "Bad param $_" }) for qw(bkd_id problem);

    my $cpid = $dbh->selectrow_array(q~
        SELECT CP.id FROM contest_problems CP
        WHERE CP.contest_id = ? AND CP.code = ?~, undef,
        $cid, $p->{problem})
        or return $p->print_json({ error => 'Bad param: problem' });

    my $login = 'bkd_2022_' . $p->{bkd_id};
    my ($aid, $user_sid, $caid, $old_diff_time) = $dbh->selectrow_array(q~
        SELECT A.id, A.sid, CA.id, CA.diff_time
        FROM accounts A
        LEFT JOIN contest_accounts CA ON A.id = CA.account_id AND CA.contest_id = ?
        WHERE A.login = ?~, undef,
        $cid, $login)
        or return $p->print_json({ error => 'User not found' });

    my $need_commit = 0;
    if (!$user_sid) {
        $user_sid = CATS::User::make_sid;
        $dbh->do(q~
            UPDATE accounts SET sid = ?, last_login = CURRENT_TIMESTAMP
            WHERE id = ?~, undef,
            $user_sid, $aid);
        $need_commit = 1;
    }
    if (!$caid) {
        CATS::User::add_to_contest(contest_id => $cid, account_id => $aid, is_remote => 1, is_ooc => 0);
        $need_commit = 1;
    }
    if (!$old_diff_time && $contest->{time_since_offset_start_until}) {
        $dbh->do(q~
            UPDATE contest_accounts SET is_ooc = 0, is_remote = 0, diff_time = ?
            WHERE contest_id = ? AND account_id = ?~, undef,
            $contest->{time_since_start}, $cid, $aid);
        $need_commit = 1;
    }
    $dbh->commit if $need_commit;

    $p->print_json({ ok => 1, url =>
        CATS::Utils::url_function('problem_text', cid => $cid, cpid => $cpid, sid => $user_sid) });
}

sub integration_bkd_get_points_api {
    my ($p) = @_;
    $is_jury or return;
    $p->{$_} || return $p->print_json({ error => "Bad param $_" }) for qw(bkd_id problem);

    my $pid = $dbh->selectrow_array(q~
        SELECT CP.problem_id FROM contest_problems CP
        WHERE CP.contest_id = ? AND CP.code = ?~, undef,
        $cid, $p->{problem})
        or return $p->print_json({ error => 'Bad param: problem' });

    my $login = 'bkd_2022_' . $p->{bkd_id};
    my ($aid) = $dbh->selectrow_array(q~
        SELECT A.id
        FROM contest_accounts CA
        INNER JOIN accounts A ON A.id = CA.account_id
        WHERE CA.contest_id = ? AND A.login = ?~, undef,
        $cid, $login)
        or return $p->print_json({ error => 'User not found' });

    my ($req_id, $state, $points) = $dbh->selectrow_array(q~
        SELECT id, state, points
        FROM reqs
        WHERE contest_id = ? AND problem_id = ? AND account_id = ?
        ORDER BY id DESC
        ROWS 1~, undef,
        $cid, $pid, $aid);
    $req_id or return $p->print_json({ error => 'No submission' });
    if (
        $state > $cats::request_processed && !defined $points
    ) {
        if ($state == $cats::st_security_violation || $state == $cats::st_manually_rejected) {
            $points = 0;
        }
        else {
            $points = $dbh->selectrow_array(q~
                SELECT SUM(COALESCE(RD.points, CASE WHEN RD.result = ? THEN T.points ELSE 0 END))
                FROM req_details RD
                INNER JOIN tests T ON T.rank = RD.test_rank AND T.problem_id = ?
                WHERE req_id = ?~, undef,
                $cats::st_accepted, $pid, $req_id);
        }
        eval {
            $dbh->do(q~
                UPDATE reqs SET points = ? WHERE id = ? AND points IS NULL~, undef,
                $points, $req_id);
            1;
        } or $CATS::DB::db->catch_deadlock_error("integration_bkd_get_points_api $req_id");
    }
    $dbh->commit;
    $p->print_json({ ok => 1, points => $points, id => $req_id });
}

sub integration_bkd_user_import_api {
    my ($p) = @_;

    $is_jury or return;
    $p->{$_} || return $p->print_json({ error => "Bad param $_" }) for qw(bkd_id name email age_group);
    $p->{age_group} =~ /^(?:1|2|3)$/
        or return $p->print_json({ error => 'Bad param age_group' });

    my $login = 'bkd_2022_' . $p->{bkd_id};
    my $caid = $dbh->selectrow_array(q~
        SELECT CA.id
        FROM contest_accounts CA
        INNER JOIN accounts A ON A.id = CA.account_id
        WHERE CA.contest_id = ? AND A.login = ?~, undef,
        $cid, $login);
    return $p->print_json({ error => 'Already exists' }) if $caid;

    my $pid = $dbh->selectrow_array(q~
        SELECT CP.problem_id FROM contest_problems CP
        WHERE CP.contest_id = ? AND CP.code = '1'~, undef,
        $cid);

    my $u = CATS::User->new;
    $u->{login} = $login;
    $u->{team_name} = $p->{name};
    $u->{passwd} = CATS::User::hash_password(rand());
    $u->insert($cid, is_ooc => 0);
    $dbh->do(q~
        UPDATE accounts SET multi_ip = 1 WHERE id = ?~, undef,
        $u->{id});

    $dbh->do(_u $sql->insert('contacts', {
        id => new_id,
        account_id => $u->{id},
        contact_type_id => $CATS::Globals::contact_email,
        handle => $p->{email},
        is_actual => 1,
    }));

    $dbh->do(_u $sql->insert('snippets', {
        id => new_id,
        account_id => $u->{id},
        problem_id => $pid,
        contest_id => $cid,
        name => 'sn_age_group',
        text => $p->{age_group},
    }));

    $dbh->commit;

    $p->print_json({ ok => $u->{id} });
}

our $form = CATS::Form->new(
    table => 'accounts A',
    fields => [
        [ name => 'team_name', caption => 625 ],
        [ name => 'first_name', db_name => '', validators => [ CATS::Field::str_length(1, 50) ] ],
        [ name => 'second_name', db_name => '', validators => [ CATS::Field::str_length(1, 50) ] ],
        [ name => 'last_name', db_name => '', validators => [ CATS::Field::str_length(1, 50) ] ],
        [ name => 'account_id', ],
    ],
    joins => [ { sql => 'LEFT JOIN accounts A ON A.id = J.account_id', fields => 'A.login AS account_name' } ],
    href_action => 'judges_edit',
    descr_field => 'nick',
    template_var => 'j',
    msg_saved => 1140,
    msg_deleted => 1020,
    before_save_db => sub {
        my ($data, $id) = @_;
        $id and return;
        $data->{is_alive} = 0;
        $data->{alive_date} = \'CURRENT_TIMESTAMP';
    },
    before_display => sub {
        my ($fd, $p) = @_;
        $fd->{de_bitmap} = $fd->{id} &&
            CATS::DB::select_row('judge_de_bitmap_cache', '*', { judge_id => $fd->{id} });
        if ($fd->{de_bitmap}) {
            my $dev_env = CATS::DevEnv->new(CATS::JudgeDB::get_DEs);
            $fd->{supported_DEs} = [
                $dev_env->by_bitmap([ CATS::DeBitmaps::extract_de_bitmap($fd->{de_bitmap}) ]) ],
        }
        if (my $aid = $fd->{indexed}->{account_id}->{value}) {
            $fd->{href_contests} = url_f('contests', search => "has_user($aid)");
        }
        $fd->{href_find_users} = url_f('api_find_users');
        $fd->{extra_fields}->{account_name} = $p->{account_name} if $p->{account_name};
    },
    validators => [ sub {
        my ($fd, $p) = @_;
        $fd->{indexed}->{account_id}->{value} = undef;
        $p->{account_name} or return 1;
        $fd->{indexed}->{account_id}->{value} = $dbh->selectrow_array(q~
            SELECT id FROM accounts WHERE login = ?~, undef,
            $p->{account_name}) and return 1;
        $fd->{account}->{error} = res_str(1139, $p->{account_name});
        undef;
    } ],
);

sub bkd_registration {
    my ($p) = @_;
    init_template($p, 'bkd_registration');
    $t->param(title => 'Ближе к Дальнему');
}

1;
