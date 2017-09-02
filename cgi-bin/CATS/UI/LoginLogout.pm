package CATS::UI::LoginLogout;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t $uid);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(auto_ext init_template url_f);
use CATS::Redirect;
use CATS::User;
use CATS::Utils qw(url_function);
use CATS::Web qw(redirect);

my $check_password;
BEGIN {
    $check_password = eval { require Authen::Passphrase; } ?
        sub {
            my ($password, $hash) = @_;
            my $p = eval { Authen::Passphrase->from_rfc2307($hash) };
            $p ? $p->match($password) : $password eq $hash;
        } :
        sub { $_[0] eq $_[1] }
}

sub split_ips { map { /(\S+)/ ? $1 : () } split ',', $_[0] }

sub login_frame {
    my ($p) = @_;
    init_template(auto_ext('login', $p->{json}));
    $t->param(href_login => url_function('login', redir => $p->{redir}));
    msg(1004) if $p->{logout};

    my $login = $p->{login};
    if (!$login) {
        $t->param(message => 'No login') if $p->{json};
        return;
    }
    $t->param(login => Encode::decode_utf8($login));

    my ($aid, $hash, $locked, $restrict_ips) = $dbh->selectrow_array(qq~
        SELECT id, passwd, locked, restrict_ips FROM accounts WHERE login = ?~, undef, $login);

    $aid && $check_password->($p->{passwd}, $hash) or return msg(1040);
    !$locked or return msg(1041);

    my $last_ip = CATS::IP::get_ip();

    if ($restrict_ips) {
        my %allowed_ips = map { $_ => 1 } split_ips($restrict_ips);
        0 < grep $allowed_ips{$_}, split_ips($last_ip) or return msg(1039);
    }

    for (1..20) {
        $sid = CATS::User::make_sid;

        $dbh->do(q~
            UPDATE accounts SET sid = ?, last_login = CURRENT_TIMESTAMP, last_ip = ?
            WHERE id = ?~, undef,
            $sid, $last_ip, $aid
        ) or next;
        $dbh->commit;

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
        return redirect(url_function($f, %params));
    }
    die 'Can not generate sid';
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
        init_template(auto_ext('logout'));
        0;
    }
    else {
       redirect(url_function('login', logout => 1));
    }
}

1;
