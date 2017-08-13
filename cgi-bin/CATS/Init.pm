package CATS::Init;

use strict;
use warnings;

use Data::Dumper;
use Storable qw();

use CATS::Contest;
use CATS::DB;
use CATS::Globals qw($contest $t $sid $cid $uid $is_root $is_jury $privs $user);
use CATS::IP;
use CATS::Messages qw(msg);
use CATS::Output qw(init_template);
use CATS::Privileges;
use CATS::Redirect;
use CATS::Settings qw($settings);
use CATS::Utils;
use CATS::Web qw(param url_param);

# Authorize user, initialize permissions and settings.
sub init_user {
    $sid = url_param('sid') || '';
    $is_root = 0;
    $privs = {};
    $uid = undef;
    $user = { privs => $privs };
    my $bad_sid = length $sid > 30;
    my $enc_settings;
    if ($sid ne '' && !$bad_sid) {
        (
            $uid, $user->{name}, my $srole, my $last_ip, my $locked,
            $user->{git_author_name}, $user->{git_author_email}, $enc_settings
        ) =
            $dbh->selectrow_array(q~
                SELECT id, team_name, srole, last_ip, locked, git_author_name, git_author_email, settings
                FROM accounts WHERE sid = ?~, undef,
                $sid);
        $bad_sid = !defined($uid) || ($last_ip || '') ne CATS::IP::get_ip() || $locked;
        if (!$bad_sid) {
            $user->{privs} = $privs = CATS::Privileges::unpack_privs($srole);
            $is_root = $privs->{is_root};
        }
    }

    CATS::Settings::init($enc_settings);

    if ($bad_sid) {
        return CATS::Web::forbidden if param('noredir');
        init_template(param('json') ? 'bad_sid.json.tt' : 'login.html.tt');
        $sid = '';
        $t->param(href_login => CATS::Utils::url_function('login', redir => CATS::Redirect::pack_params));
        msg(1002);
    }
}

sub extract_cid_from_cpid {
    my $cpid = url_param('cpid') or return;
    return $dbh->selectrow_array(qq~
        SELECT contest_id FROM contest_problems WHERE id = ?~, undef,
        $cpid);
}

sub init_contest {
    $cid = url_param('cid') || param('clist') || extract_cid_from_cpid || $settings->{contest_id} || '';
    $cid =~ s/^(\d+).*$/$1/; # Get first contest if from clist.
    if ($contest && ref $contest ne 'CATS::Contest') {
        warn "Strange contest: $contest from ", $ENV{HTTP_REFERER} || '';
        warn Dumper($contest);
        undef $contest;
    }
    $contest ||= CATS::Contest->new;
    $contest->load($cid);
    $settings->{contest_id} = $cid = $contest->{id};

    $user->{diff_time} = 0;
    $is_jury = $user->{is_virtual} = $user->{is_participant} = 0;
    # Authorize user in the contest.
    if (defined $uid) {
        (
            $user->{ca_id}, $user->{is_participant}, $is_jury, $user->{site_id}, $user->{is_site_org},
            $user->{is_virtual}, $user->{is_remote},
            $user->{personal_diff_time}, $user->{diff_time},
            $user->{personal_ext_time}, $user->{ext_time},
            $user->{site_name}
        ) = $dbh->selectrow_array(q~
            SELECT
                CA.id, 1, CA.is_jury, CA.site_id, CA.is_site_org,
                CA.is_virtual, CA.is_remote,
                CA.diff_time, COALESCE(CA.diff_time, 0) + COALESCE(CS.diff_time, 0),
                CA.ext_time, COALESCE(CA.ext_time, 0) + COALESCE(CS.ext_time, 0),
                S.name
            FROM contest_accounts CA
            LEFT JOIN contest_sites CS ON CS.contest_id = CA.contest_id AND CS.site_id = CA.site_id
            LEFT JOIN sites S ON S.id = CA.site_id
            WHERE CA.contest_id = ? AND CA.account_id = ?~, undef,
            $cid, $uid);
        $user->{diff_time} ||= 0;
        $is_jury ||= $is_root;
    }
    else {
        $user->{anonymous_id} = $dbh->selectrow_array(q~
            SELECT id FROM accounts WHERE login = ?~, undef,
            $cats::anonymous_login);
    }
    $user->{is_jury} = $is_jury;
    if ($contest->{is_hidden} && !$user->{is_participant}) {
        # If user tries to look at a hidden contest, show training instead.
        $contest->load(0);
        $settings->{contest_id} = $cid = $contest->{id};
    }
}

sub initialize {
    $Storable::canonical = 1;
    CATS::Messages::init;
    $t = undef;
    init_user;
    init_contest;
}

1;
