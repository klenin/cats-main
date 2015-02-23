package CATS::UI::LoginLogout;

use strict;
use warnings;

use CATS::Web qw(param url_param);
use CATS::DB;
use CATS::Constants;
use CATS::Misc qw(
    $t $is_jury $is_root $is_team $sid $cid $uid $contest $is_virtual $settings
    init_template init_listview_template msg res_str url_f auto_ext);
use CATS::Utils qw(url_function);
use CATS::Web qw(redirect);

sub make_sid {
    my @ch = ('A'..'Z', 'a'..'z', '0'..'9');
    join '', map { $ch[rand @ch] } 1..30;
}

sub login_frame
{
    my $json = param('json');
    init_template(auto_ext('login', $json));
    $t->param(href_login => url_function('login'));
    msg(1004) if param('logout');

    my $login = param('login');
    if (!$login) {
        $t->param(message => 'No login') if $json;
        return;
    }
    $t->param(login => Encode::decode_utf8($login));
    my $passwd = param('passwd');

    my ($aid, $passwd2, $locked) = $dbh->selectrow_array(qq~
        SELECT id, passwd, locked FROM accounts WHERE login = ?~, undef, $login);

    $aid && $passwd2 eq $passwd or return msg(1040);
    !$locked or return msg(1041);

    my $last_ip = CATS::IP::get_ip();

    my $cid = url_param('cid');
    for (1..20) {
        $sid = make_sid;

        $dbh->do(qq~
            UPDATE accounts SET sid = ?, last_login = CURRENT_TIMESTAMP, last_ip = ?
                WHERE id = ?~,
            {}, $sid, $last_ip, $aid
        ) or next;
        $dbh->commit;

        if ($json) {
            $contest->load($cid, ['id']);
            $t->param(sid => $sid, cid => $contest->{id});
            return;
        }
        $t = undef;
        return redirect(url_function('contests', sid => $sid, cid => $cid));
    }
    die 'Can not generate sid';
}

sub logout_frame
{
    $cid = '';
    $sid = '';
    if ($uid) {
        $dbh->do(qq~UPDATE accounts SET sid = NULL WHERE id = ?~, {}, $uid);
        $dbh->commit;
    }
    if (param('json')) {
        init_template(auto_ext('logout'));
        0;
    }
    else {
       redirect(url_function('login', logout => 1));
    }
}

1;
