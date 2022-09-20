package CATS::UI::LoginLogout;

use strict;
use warnings;

use Digest::SHA;
use Encode;

use CATS::Config;
use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t $uid);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::Privileges;
use CATS::Redirect;
use CATS::User;
use CATS::Utils qw(url_function);

my $check_password;
BEGIN {
    $check_password = eval { require Authen::Passphrase; } ?
        sub {
            my ($password, $hash) = @_;
            $password = Encode::is_utf8($password) ? Encode::encode_utf8($password) : $password;
            my $p = eval { Authen::Passphrase->from_rfc2307($hash) };
            $p ? $p->match($password) : $password eq $hash;
        } :
        sub { $_[0] eq $_[1] }
}

sub split_ips { map { /(\S+)/ ? $1 : () } split ',', $_[0] }

sub _ensure_good_sid {
    my ($current_ip, $aid) = @_;
    for (1..20) {
        $dbh->do(q~
            UPDATE accounts A SET sid = ?, last_login = CURRENT_TIMESTAMP, last_ip = ?
            WHERE A.id = ? AND
                NOT EXISTS (SELECT 1 FROM accounts A1 WHERE A1.sid = ? AND A1.id <> ?)~, undef,
            $sid, $current_ip, $aid, $sid, $aid
        ) and return $dbh->commit;
        $sid = CATS::User::make_sid;
    }
    die 'Can not generate sid';
}

sub _token_no_salt {
    my ($p) = @_;
    my ($account_id, $usages_left) = $dbh->selectrow_array(q~
        SELECT account_id, usages_left FROM account_tokens WHERE token = ?~, undef,
        $p->{token}) or return msg(1040);
    my $token_cond = { token => $p->{token} };
    my @s = ($usages_left // 0) == 1 ?
        $sql->delete('account_tokens', $token_cond) :
        $sql->update('account_tokens', {
            referer => $p->referer || undef,
            last_used => \'CURRENT_TIMESTAMP',
            usages_left => $usages_left && $usages_left - 1 },
            $token_cond);
    $dbh->do(_u @s) or return;
    $account_id;
}

sub _login_failed {
    my ($p, $srole) = @_;
    $p->log_info(sprintf "Failed root login as '%s'", $p->{login})
        if CATS::Privileges::is_root($srole);
    msg(1040);
}

sub login_frame {
    my ($p) = @_;
    init_template($p, 'login');
    $t->param(href_login => url_function('login', redir => $p->{redir}));
    msg(1004) if $p->{logout};

    my $where = {};
    if ($p->{token} && !$p->{salt}) {
        $where->{id} = _token_no_salt($p) or return;
    }
    elsif ($p->{login}) {
        $where->{login} = $p->{login};
        $t->param(login => $p->{login} || '');
    }
    else {
        return $p->{json} && msg(1040);
    }

    my ($aid, $hash, $locked, $restrict_ips, $last_ip, $last_sid, $srole) = $dbh->selectrow_array(
        _u $sql->select('accounts', [qw(id passwd locked restrict_ips last_ip sid srole)], $where));

    $aid or return msg(1040);

    if ($p->{token} && $p->{salt}) {
        my $tokens = $dbh->selectall_arrayref(q~
            SELECT token, referer FROM account_tokens WHERE account_id = ?~, { Slice => {} },
            $aid) or return msg(1040);
        my $found;
        for (@$tokens) {
            if (Digest::SHA::hmac_sha1_hex($_->{token}, $p->{salt}) eq $p->{token}) {
                $found = 1;
                last;
            }
        }
        $found or return _login_failed($p, $srole);
    }
    elsif (!$p->{token}) {
        defined $hash && $check_password->($p->{passwd} // '', $hash) or return _login_failed($p, $srole);
    }
    !$locked or return msg(1041);

    my $current_ip = CATS::IP::get_ip();

    if ($restrict_ips) {
        my %allowed_ips = map { $_ => 1 } split_ips($restrict_ips);
        0 < grep $allowed_ips{$_}, split_ips($current_ip) or return msg(1039);
    }

    $sid = ($last_ip eq $current_ip ? $last_sid : undef) // CATS::User::make_sid;
    _ensure_good_sid($current_ip, $aid);

    if ($p->{json}) {
        $contest->load($p->{cid}, [ 'id' ]);
        $t->param(sid => $sid, cid => $contest->{id});
        return;
    }
    $t = undef;
    my %params = CATS::Redirect::unpack_params($p->{redir});
    my $f = $params{f} || 'contests';
    delete $params{f};
    $params{sid} = $sid;
    $params{cid} ||= $p->{cid};
    $p->redirect(url_function $f, %params);
}

sub logout_frame {
    my ($p) = @_;
    $cid = '';
    $sid = '';
    if ($uid) {
        $dbh->do(q~
            UPDATE accounts SET sid = NULL WHERE id = ?~, undef,
            $uid);
        $dbh->commit;
    }
    if ($p->{json}) {
        init_template($p, 'logout');
        0;
    }
    else {
       $p->redirect(url_function 'login', logout => 1);
    }
}

sub _login_token {
    my ($p) = @_;
    # ONTI compatibility.
    $p->{apikey} ||= $p->{token};

    $p->{$_} or return { ok => 0, erro => "no param '$_'" } for qw(apikey cid);
    my ($apikey, $login_prefix) = $dbh->selectrow_array(q~
        SELECT C.apikey, C.login_prefix FROM contests C WHERE C.id = ?~, undef,
        $p->{cid});
    $p->{apikey} eq ($apikey // '') or return { ok => 0, error => 'bad api key' };

    $p->{login} ||= ($login_prefix // '') . ($p->{team_id} // '')
        or return { ok => 0, msg => "no param 'login'" };

    my ($account_id, $is_jury_in_contest, $name) = $dbh->selectrow_array(q~
        SELECT CA.account_id, CA.is_jury, A.team_name FROM contest_accounts CA
        INNER JOIN accounts A ON A.id = CA.account_id
        WHERE A.login = ? AND CA.contest_id = ?~, undef,
        $p->{login}, $p->{cid}) or return { ok => 0, error => 'bad login' };
    $is_jury_in_contest and return { ok => 0, error => 'bad user' };
    my $token = CATS::User::make_token($account_id);
    {
        ok => 1,
        url => CATS::Utils::absolute_url_function(
            'login', cid => $p->{cid}, token => $token, redir => $p->{redir}),
        name => $name,
        id => $account_id,
    };
}

sub login_token_api {
    my ($p) = @_;
    my $r = _login_token($p);
    $p->print_json($r);
}

sub login_available_api {
    my ($p) = @_;
    $p->print_json({
        available => CATS::User::is_login_available($p->{login}, $p->{id}) ? 1 : 0 });
}

1;
