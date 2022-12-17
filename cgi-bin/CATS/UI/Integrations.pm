package CATS::UI::Integrations;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($cid $is_jury);
use CATS::Output qw(url_f);
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
    my ($aid, $user_sid) = $dbh->selectrow_array(q~
        SELECT A.id, A.sid
        FROM contest_accounts CA
        INNER JOIN accounts A ON A.id = CA.account_id
        WHERE CA.contest_id = ? AND A.login = ?~, undef,
        $cid, $login)
        or return $p->print_json({ error => 'User not found' });
    if (!$user_sid) {
        $user_sid = CATS::User::make_sid;
        $dbh->do(q~
            UPDATE accounts SET sid = ? WHERE id = ?~, undef,
            $user_sid, $aid);
        $dbh->commit;
    }

    $p->print_json({ ok => 1, url =>
        CATS::Utils::url_function('problem_text', cid => $cid, cpid => $cpid, sid => $user_sid) });
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
    $u->insert($cid);
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

1;
