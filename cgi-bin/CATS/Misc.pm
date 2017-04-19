package CATS::Misc;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT = qw(
    get_anonymous_uid
    initialize
    auto_ext
    format_diff_time
    init_template
    generate_output
    http_header
    msg
    url_f
    templates_path
    downloads_path
    downloads_url
    res_str
    attach_menu
    save_settings
    references_menu
    prepare_server_time
    problem_status_names
    pack_redir_params
    unpack_redir_params
    unpack_privs
);

our @EXPORT_OK = qw(
    $contest $t $sid $cid $uid $git_author_name $git_author_email
    $is_root $is_team $is_jury $privs $is_virtual $virtual_diff_time
    $init_time $settings);

#use CGI::Fast( ':standard' );
#use CGI::Util qw(rearrange unescape escape);
#use FCGI;

use Carp qw(croak);
use Encode();
use MIME::Base64;
use SQL::Abstract;
use Storable;
use Time::HiRes;

use CATS::Config qw(cats_dir);
use CATS::Constants;
use CATS::Contest;
use CATS::DB;
use CATS::IP;
use CATS::Template;
use CATS::Utils qw();
use CATS::Web qw(param url_param headers content_type cookie);

our (
    $contest, $t, $sid, $cid, $uid, $team_name, $dbi_error, $git_author_name, $git_author_email,
    $is_root, $is_team, $is_jury, $privs, $is_virtual, $virtual_diff_time,
    $request_start_time, $init_time, $settings
);

my ($messages, $http_mime_type, %extra_headers, $enc_settings);

sub get_anonymous_uid
{
    scalar $dbh->selectrow_array(qq~
        SELECT id FROM accounts WHERE login = ?~, undef, $cats::anonymous_login);
}


sub http_header
{
    my ($type, $encoding, $cookie) = @_;

    content_type($type, $encoding);
    headers(cookie => $cookie, %extra_headers);
}


sub templates_path
{
    my $template = param('iface') || '';

    for (@cats::templates)
    {
        if ($template eq $_->{id})
        {
            return $_->{path};
        }
    }

    cats_dir() . $cats::templates[0]->{path};
}

sub downloads_path { cats_dir() . '../download/' }
sub downloads_url { 'download/' }

sub lang { $settings->{lang} || 'ru' }

sub init_messages_lang {
    my ($lang) = @_;
    my $msg_file = cats_dir() . "../tt/lang/$lang/strings";

    my $r = [];
    open my $f, '<', $msg_file or
        die "Couldn't open message file: '$msg_file'.";
    binmode($f, ':utf8');
    while (my $line = <$f>) {
        $line =~ m/^(\d+)\s+\"(.*)\"\s*$/ or next;
        $r->[$1] and die "Duplicate message id: $1";
        $r->[$1] = $2;
    }
    $r;
}

sub auto_ext
{
    my ($file_name, $json) = @_;
    my $ext = $json // param('json') ? 'json' : 'html';
    "$file_name.$ext.tt";
}


#my $template_file;
sub init_template
{
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


sub selected_menu_item
{
    my $default = shift || '';
    my $href = shift;

    my ($pf) = ($href =~ /[?;]f=([a-z_]+)/);
    $pf ||= '';
    #my $q = new CGI((split('\?', $href))[1]);

    my $page = url_param('f');
    #my $pf = $q->param('f') || '';

    (defined $page && $pf eq $page) ||
    (!defined $page && $pf eq $default);
}


sub mark_selected
{
    my ($default, $menu) = @_;

    for my $i (@$menu)
    {
        if (selected_menu_item($default, $i->{href}))
        {
            $i->{selected} = 1;
            $i->{dropped} = 1;
        }

        my $submenu = $i->{submenu};
        for my $j (@$submenu)
        {
            if (selected_menu_item($default, $j->{href}))
            {
                $j->{selected} = 1;
                $i->{dropped} = 1;
            }
        }
    }
}


sub attach_menu
{
   my ($menu_name, $default, $menu) = @_;
   mark_selected($default, $menu);

   $t->param($menu_name => $menu);
}


sub res_str
{
    my $id = shift;
    my $t = $messages->{lang()}->[$id] or die "Unknown res_str id: $id";
    sprintf($t, @_);
}


sub msg
{
    defined $t or croak q~Call to 'msg' before 'init_template'~;
    $t->param(message => res_str(@_));
    undef;
}


sub url_f
{
    CATS::Utils::url_function(@_, sid => $sid, cid => $cid);
}

sub prepare_server_time {
    my $dt = $contest->{time_since_start} - $virtual_diff_time;
    $t->param(
        server_time => $contest->{server_time},
        elapsed_msg => res_str($dt < 0 ? 578 : 579),
        elapsed_time => format_diff_time(abs($dt)),
    );
}

sub generate_output
{
    my ($output_file) = @_;
    defined $t or return; #? undef : ref $t eq 'SCALAR' ? return : die 'Template not defined';
    $contest->{time_since_start} or warn 'No contest from: ', $ENV{HTTP_REFERER} || '';
    $t->param(
        contest_title => $contest->{title},
        current_team_name => $team_name,
        is_virtual => $is_virtual,
        virtual_diff_time => $virtual_diff_time,
        dbi_profile => $dbh->{Profile}->{Data}->[0],
        #dbi_profile => Data::Dumper::Dumper($dbh->{Profile}->{Data}),
        langs => [ map { href => url_f('contests', lang => $_), name => $_ }, @cats::langs ],
    );
    prepare_server_time;

    if (defined $dbi_error)
    {
        $t->param(dbi_error => $dbi_error);
    }
    unless (param('notime'))
    {
        $t->param(request_process_time => sprintf '%.3fs',
            Time::HiRes::tv_interval($request_start_time, [ Time::HiRes::gettimeofday ]));
        $t->param(init_time => sprintf '%.3fs', $init_time || 0);
    }
    my $cookie = $uid && lang eq 'ru' ? undef : cookie(
        -name => 'settings',
        -value => encode_base64($uid ? Storable::freeze({ lang => lang }): $enc_settings),
        -expires => '+1h');
    my $out = '';
    if (my $enc = param('enc'))
    {
        $t->param(encoding => $enc);
        http_header($http_mime_type, $enc, $cookie);
        CATS::Web::print($out = Encode::encode($enc, $t->output, Encode::FB_XMLCREF));
    }
    else
    {
        $t->param(encoding => 'UTF-8');
        http_header($http_mime_type, 'utf-8', $cookie);
        CATS::Web::print($out = $t->output);
    }
    if ($output_file)
    {
        open my $f, '>:utf8', $output_file
            or die "Error opening $output_file: $!";
        print $f $out;
    }
}

sub unpack_privs
{
    my ($srole) = @_;
    my $p = {};
    my $r = $p->{is_root} = $srole == $cats::srole_root;
    $p->{create_contests} = $r || ($srole & $cats::srole_contests_creator);
    $p->{moderate_messages} = $r || ($srole & $cats::srole_messages_moderator);
    $p;
}

sub pack_redir_params {
    encode_base64(Storable::nfreeze
        { map { $_ ne 'sid' ? ($_ => url_param($_)) : () } url_param })
}

sub unpack_redir_params {
    my ($redir) = @_;
    $redir or return ();
    my $params = Storable::thaw(decode_base64($redir));
    defined $params and return %$params;
    warn "Unable to decode redir '$redir'";
    return ();
}

# Authorize user, initialize permissions and settings.
sub init_user
{
    $sid = url_param('sid') || '';
    $is_root = 0;
    $privs = {};
    $uid = undef;
    $team_name = undef;
    $git_author_name = undef;
    $git_author_email = undef;
    my $bad_sid = length $sid > 30;
    if ($sid ne '' && !$bad_sid) {
        ($uid, $team_name, my $srole, my $last_ip, my $locked, $git_author_name, $git_author_email, $enc_settings) =
            $dbh->selectrow_array(q~
                SELECT id, team_name, srole, last_ip, locked, git_author_name, git_author_email, settings
                FROM accounts WHERE sid = ?~, undef,
                $sid);
        $bad_sid = !defined($uid) || ($last_ip || '') ne CATS::IP::get_ip() || $locked;
        if (!$bad_sid) {
            $privs = unpack_privs($srole);
            $is_root = $privs->{is_root};
        }
    }
    if (!$uid) {
        $enc_settings = cookie('settings') || '';
        $enc_settings = decode_base64($enc_settings) if $enc_settings;
    }
    # If any problem happens during the thaw, clear settings.
    $settings = eval { $enc_settings && Storable::thaw($enc_settings) } || {};

    my $lang = param('lang');
    $settings->{lang} = $lang if $lang && grep $_ eq $lang, @cats::langs;

    if ($bad_sid) {
        return CATS::Web::forbidden if param('noredir');
        init_template(param('json') ? 'bad_sid.json.tt' : 'login.html.tt');
        $sid = '';
        $t->param(href_login => CATS::Utils::url_function('login', redir => pack_redir_params));
        msg(1002);
    }
}

sub extract_cid_from_cpid
{
    my $cpid = url_param('cpid') or return;
    return $dbh->selectrow_array(qq~
        SELECT contest_id FROM contest_problems WHERE id = ?~, undef,
        $cpid);
}

sub init_contest
{
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

    $virtual_diff_time = 0;
    # Authorize user in the contest.
    $is_jury = $is_team = $is_virtual = 0;
    if (defined $uid)
    {
        ($is_team, $is_jury, $is_virtual, $virtual_diff_time) = $dbh->selectrow_array(qq~
            SELECT 1, is_jury, is_virtual, diff_time
            FROM contest_accounts WHERE contest_id = ? AND account_id = ?~, {}, $cid, $uid);
        $virtual_diff_time ||= 0;
        $is_jury ||= $is_root;
    }
    if ($contest->{is_hidden} && !$is_team)
    {
        # If user tries to look at a hidden contest, show training instead.
        $contest->load(0);
        $settings->{contest_id} = $cid = $contest->{id};
    }
    # Only guest access before the start of the contest.
    $is_team &&= $is_jury || $contest->has_started($virtual_diff_time);
}


sub save_settings
{
    my $new_enc_settings = Storable::freeze($settings);
    $new_enc_settings ne ($enc_settings || '') or return;
    $enc_settings = $new_enc_settings;
    $uid or return;
    $dbh->commit;
    $dbh->do(q~
        UPDATE accounts SET settings = ? WHERE id = ?~, undef,
        $new_enc_settings, $uid);
    $dbh->commit;
}


sub initialize
{
    $Storable::canonical = 1;
    $dbi_error = undef;
    $messages //= { map { $_ => init_messages_lang($_) } @cats::langs };
    $t = undef;
    init_user;
    init_contest;
}


sub reference_names()
{
    (
        { name => 'compilers', new => 542, item => 517 },
        { name => 'judges', new => 512, item => 511 },
        { name => 'keywords', new => 550, item => 549 },
        { name => 'import_sources', item => 557 },
        ($is_root ? { name => 'prizes', item => 565 } : ()),
    )
}


sub references_menu
{
    my ($ref_name) = @_;

    my @result;
    for (reference_names()) {
        my $sel = $_->{name} eq $ref_name;
        push @result,
            { href => url_f($_->{name}), item => res_str($_->{item}), selected => $sel };
        if ($sel && $is_root && $_->{new}) {
            unshift @result,
                { href => url_f($_->{name}, new => 1), item => res_str($_->{new}) };
        }
        $t->param(title_suffix => res_str($_->{item})) if $sel;
    }
    @result;
}


sub problem_status_names()
{+{
    $cats::problem_st_manual    => res_str(700),
    $cats::problem_st_ready     => res_str(701),
    $cats::problem_st_compile   => res_str(705),
    $cats::problem_st_suspended => res_str(702),
    $cats::problem_st_disabled  => res_str(703),
    $cats::problem_st_hidden    => res_str(704),
}}


sub run_method_enum()
{+{
    default => $cats::rm_default,
    interactive => $cats::rm_interactive,
    competitive => $cats::rm_competitive,
}}


sub format_diff_time {
    my ($dt, $display_plus) = @_;
    $dt or return '';
    my $sign = $dt < 0 ? '-' : $display_plus ? '+' : '';
    $dt = abs($dt);
    my $days = int($dt);
    $dt = ($dt - $days) * 24;
    my $hours = int($dt);
    $dt = ($dt - $hours) * 60;
    my $minutes = int($dt + 0.5);
    !$days && !$hours ? $minutes :
        sprintf($days ? '%s%d%s %02d:%02d' : '%s%4$d:%5$02d', $sign, $days, res_str(577), $hours, $minutes);
}

1;
