package CATS::Misc;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT = qw(
    auto_ext
    downloads_path
    downloads_url
    generate_output
    initialize
    init_template
    msg
    res_str
    url_f
);

our @EXPORT_OK = qw(
    $contest $t $sid $cid $uid
    $is_root $is_team $is_jury $privs $user);

#use CGI::Fast( ':standard' );
#use CGI::Util qw(rearrange unescape escape);
#use FCGI;

use Carp qw(croak);
use Encode();
use SQL::Abstract; # Actually used by CATS::DB, bit is optional there.
use Storable;

use CATS::Config qw(cats_dir);
use CATS::Constants;
use CATS::Contest;
use CATS::DB;
use CATS::IP;
use CATS::Messages;
use CATS::Privileges;
use CATS::Redirect;
use CATS::Settings qw($settings);
use CATS::Template;
use CATS::Utils qw();
use CATS::Web qw(param url_param headers content_type);

our (
    $contest, $t, $sid, $cid, $uid,
    $is_root, $is_team, $is_jury, $privs, $user,
);

my ($http_mime_type, %extra_headers);

sub http_header {
    my ($type, $encoding, $cookie) = @_;

    content_type($type, $encoding);
    headers(cookie => $cookie, %extra_headers);
}

sub downloads_path { cats_dir() . '../download/' }
sub downloads_url { 'download/' }

sub lang { goto &CATS::Messages::lang; }

sub auto_ext {
    my ($file_name, $json) = @_;
    my $ext = $json // param('json') ? 'json' : 'html';
    "$file_name.$ext.tt";
}

#my $template_file;
sub init_template {
    my ($file_name, $p) = @_;
    #if (defined $t && $template_file eq $file_name) { $t->param(tf=>1); return; }

    my ($base_name, $ext) = $file_name =~ /^(\w+)\.(\w+)(:?\.tt)$/;
    $http_mime_type = {
        htm => 'text/html',
        html => 'text/html',
        xml => 'application/xml',
        ics => 'text/calendar',
        json => 'application/json',
    }->{$ext} or die 'Unknown template extension';
    %extra_headers = $ext eq 'ics' ?
        ('Content-Disposition' => "inline;filename=$base_name.ics") : ();
    #$template_file = $file_name;
    $t = CATS::Template->new($file_name, cats_dir(), $p);
    my $json = param('json') || '';
    $extra_headers{'Access-Control-Allow-Origin'} = '*' if $json;
    $t->param(lang => lang, $json =~ /^[a-zA-Z][a-zA-Z0-9_]+$/ ? (jsonp => $json) : ());
}

*res_str = *CATS::Messages::res_str;

sub msg {
    defined $t or croak q~Call to 'msg' before 'init_template'~;
    $t->param(message => res_str(@_));
    undef;
}

sub url_f { CATS::Utils::url_function(@_, sid => $sid, cid => $cid) }

sub generate_output {
    my ($output_file) = @_;
    defined $t or return; #? undef : ref $t eq 'SCALAR' ? return : die 'Template not defined';
    $contest->{time_since_start} or warn 'No contest from: ', $ENV{HTTP_REFERER} || '';
    $t->param(
        contest_title => $contest->{title},
        user => $user,
        dbi_profile => $dbh->{Profile}->{Data}->[0],
        #dbi_profile => Data::Dumper::Dumper($dbh->{Profile}->{Data}),
        langs => [ map { href => url_f('contests', lang => $_), name => $_ }, @cats::langs ],
    );

    my $cookie = CATS::Settings::as_cookie(lang);
    my $out = '';
    if (my $enc = param('enc')) {
        $t->param(encoding => $enc);
        http_header($http_mime_type, $enc, $cookie);
        CATS::Web::print($out = Encode::encode($enc, $t->output, Encode::FB_XMLCREF));
    }
    else {
        $t->param(encoding => 'UTF-8');
        http_header($http_mime_type, 'utf-8', $cookie);
        CATS::Web::print($out = $t->output);
    }
    if ($output_file) {
        open my $f, '>:utf8', $output_file
            or die "Error opening $output_file: $!";
        print $f $out;
    }
}

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
            $privs = CATS::Privileges::unpack_privs($srole);
            $is_root = $privs->{is_root};
        }
    }

    CATS::Settings::init($uid, $enc_settings);
    CATS::Messages::init_lang($settings);

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
        use Data::Dumper;
        warn "Strange contest: $contest from ", $ENV{HTTP_REFERER} || '';
        warn Dumper($contest);
        undef $contest;
    }
    $contest ||= CATS::Contest->new;
    $contest->load($cid);
    $settings->{contest_id} = $cid = $contest->{id};

    $user->{diff_time} = 0;
    $is_jury = $is_team = $user->{is_virtual} = $user->{is_participant} = 0;
    # Authorize user in the contest.
    if (defined $uid) {
        (
            $user->{ca_id}, $is_team, $is_jury, $user->{site_id}, $user->{is_site_org},
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
        $user->{is_participant} = $is_team;
        $is_jury ||= $is_root;
    }
    else {
        $user->{anonymous_id} = $dbh->selectrow_array(q~
            SELECT id FROM accounts WHERE login = ?~, undef,
            $cats::anonymous_login);
    }
    $user->{is_jury} = $is_jury;
    if ($contest->{is_hidden} && !$is_team) {
        # If user tries to look at a hidden contest, show training instead.
        $contest->load(0);
        $settings->{contest_id} = $cid = $contest->{id};
    }
    # Only guest access before the start of the contest.
    $is_team &&= $is_jury || $contest->has_started($user->{diff_time});
}

sub initialize {
    $Storable::canonical = 1;
    CATS::Messages::init;
    $t = undef;
    init_user;
    init_contest;
}

sub run_method_enum() {+{
    default => $cats::rm_default,
    interactive => $cats::rm_interactive,
    competitive => $cats::rm_competitive,
}}

1;
