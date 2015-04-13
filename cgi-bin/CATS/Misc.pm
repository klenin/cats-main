package CATS::Misc;

use strict;
use warnings;

BEGIN
{
    use Exporter;

    no strict;
    @ISA = qw(Exporter);
    @EXPORT = qw(
        cats_dir
        get_anonymous_uid
        initialize
        auto_ext
        init_template
        init_listview_template
        generate_output
        http_header
        msg
        url_f
        templates_path
        order_by
        sort_listview
        define_columns
        res_str
        attach_listview
        attach_menu
        save_settings
        references_menu
        problem_status_names
    );

    @EXPORT_OK = qw(
        $contest $t $sid $cid $uid $git_author_name $git_author_email
        $is_root $is_team $is_jury $is_virtual $virtual_diff_time
        $listview_name $init_time $settings);

    %EXPORT_TAGS = (all => [ @EXPORT, @EXPORT_OK ]);
}

use CATS::Template;
#use CGI::Fast( ':standard' );
use CATS::Web qw(param url_param headers content_type cookie);
#use CGI::Util qw(rearrange unescape escape);
use MIME::Base64;
use Storable;
use List::Util qw(first min max);

#use FCGI;
use SQL::Abstract;
use Digest::MD5;
use Time::HiRes;
use Encode;

use CATS::DB;
use CATS::Constants;
use CATS::IP;
use CATS::Contest;
use CATS::Utils qw();


use vars qw(
    $contest $t $sid $cid $uid $team_name $dbi_error $git_author_name $git_author_email
    $is_root $is_team $is_jury $can_create_contests $is_virtual $virtual_diff_time
    $listview_name $col_defs $request_start_time $init_time $settings
);

my ($listview_array_name, $messages, $http_mime_type, %extra_headers, $enc_settings);

# Optimization: limit datasets by both maximum row count and maximum visible pages.
my $max_fetch_row_count = 1000;
my $visible_pages = 5;

my @display_rows = (10, 20, 30, 40, 50, 100, 300);

my $cats_dir;
sub cats_dir()
{
    $cats_dir ||= $ENV{CATS_DIR} || '/usr/local/apache/CATS/cgi-bin/';
}


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

sub init_listview_params
{
    $_ && ref $_ eq 'HASH' or $_ = {} for $settings->{$listview_name};
    my $s = $settings->{$listview_name};
    $s->{search} ||= '';

    $s->{page} = url_param('page') if defined url_param('page');

    my $search = decode_utf8(param('search'));
    if (defined $search)
    {
        if ($s->{search} ne $search)
        {
            $s->{search} = $search;
            $s->{page} = 0;
        }
    }

    if (defined url_param('sort'))
    {
        $s->{sort_by} = int(url_param('sort'));
        $s->{page} = 0;
    }

    if (defined url_param('sort_dir'))
    {
        $s->{sort_dir} = int(url_param('sort_dir'));
        $s->{page} = 0;
    }

    $s->{rows} ||= $display_rows[0];
    my $rows = param('rows') || 0;
    if ($rows > 0) {
        $s->{page} = 0 if $s->{rows} != $rows;
        $s->{rows} = $rows;
    }
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
    $t->param(lang => lang);
;}


sub init_listview_template
{
    ($listview_name, $listview_array_name, my $file_name, my $p) = @_;

    init_listview_params;

    init_template($file_name, $p);
}


sub selected_menu_item
{
    my $default = shift || '';
    my $href = shift;

    my ($pf) = ($href =~ /\?f=([a-z_]+)/);
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
    $t->param(message => res_str(@_));
    undef;
}


sub url_f
{
    CATS::Utils::url_function(@_, sid => $sid, cid => $cid);
}


sub attach_listview
{
    my ($url, $fetch_row, $sth, $p) = @_;
    $listview_name or die;
    my $s = $settings->{$listview_name};

    my ($row_count, $page_count, @data) = (0, 0);
    my $page = \$s->{page};
    $$page ||= 0;
    my $rows = $s->{rows} || 1;

    # <search> = <condition> { ',' <condition> }
    # <condition> = <value> | <field name> '=' <value>
    # Values without field name are searched in all fields.
    # Different fields are AND'ed, multiple values of the same field are OR'ed.
    my %mask;
    for my $q (split ',', $s->{search}) {
        my ($k, $v) = $q =~ /^(.*)=(.*)$/ ? ($1, $2) : ('', $q);
        push @{$mask{$k} ||= []}, $v;
    }
    for (values %mask) {
        my $s = join '|', map "\Q$_\E", @$_;
        $_ = qr/$s/i;
    }

    ROWS: while (my %row = $fetch_row->($sth)) {
        last if $row_count > $max_fetch_row_count || $page_count > $$page + $visible_pages;
        for my $key (keys %mask) {
            first { defined $_ && Encode::decode_utf8($_) =~ $mask{$key} }
                ($key ? ($row{$key}) : values %row)
                or next ROWS;
        }
        ++$row_count;
        $page_count = int(($row_count + $rows - 1) / $rows);
        next if $page_count > $$page + 1;
        # Remember the last visible page data in case of a too large requested page number.
        @data = () if @data == $rows;
        push @data, \%row;
    }

    $$page = min(max($page_count - 1, 0), $$page);
    my $range_start = max($$page - int($visible_pages / 2), 0);
    my $range_end = min($range_start + $visible_pages - 1, $page_count - 1);

    my $pp = $p->{page_params} || {};
    my $page_extra_params = join '', map ";$_=$pp->{$_}", keys %$pp;
    my $href_page = sub { "$url$page_extra_params;page=$_[0]" };
    my @pages = map {{
        page_number => $_ + 1,
        href_page => $href_page->($_),
        current_page => $_ == $$page
    }} $range_start..$range_end;

    $t->param(
        page => $$page, pages => \@pages, search => $s->{search},
        ($range_start > 0 ? (href_prev_pages => $href_page->($range_start - 1)) : ()),
        ($range_end < $page_count - 1 ? (href_next_pages => $href_page->($range_end + 1)) : ()),
        display_rows =>
            [ map { value => $_, text => $_, selected => $s->{rows} == $_ }, @display_rows ],
        $listview_array_name => \@data,
    );
}


sub check_sortable_field
{
    my $s = shift;
    return defined $s->{sort_by} && $s->{sort_by} =~ /^\d+$/ && $col_defs->[$s->{sort_by}]
}


sub order_by
{
    my $s = $settings->{$listview_name};
    check_sortable_field($s) or return '';
    sprintf 'ORDER BY %s %s',
        $col_defs->[$s->{sort_by}]{order_by}, ($s->{sort_dir} ? 'DESC' : 'ASC');
}


sub sort_listview
{
    my $data = shift;
    my $s = $settings->{$listview_name};
    check_sortable_field($s) or return $data;
    my $order_by = $col_defs->[$s->{sort_by}]{order_by};
    my $cmp = $s->{sort_dir} ?
        sub { $a->{$order_by} cmp $b->{$order_by} } :
        sub { $b->{$order_by} cmp $a->{$order_by} };
    [ sort $cmp @$data ];
}


sub generate_output
{
    my ($output_file) = @_;
    defined $t or return; #? undef : ref $t eq 'SCALAR' ? return : die 'Template not defined';
    $contest->{time_since_start} or warn 'No contest from: ', $ENV{HTTP_REFERER} || '';
    $t->param(
        contest_title => $contest->{title},
        server_time => $contest->{server_time},
    	current_team_name => $team_name,
    	is_virtual => $is_virtual,
    	virtual_diff_time => $virtual_diff_time);

    my $elapsed_minutes = int(($contest->{time_since_start} - $virtual_diff_time) * 1440);
    if ($elapsed_minutes < 0)
    {
        $t->param(show_remaining_minutes => 1, remaining_minutes => -$elapsed_minutes);
    }
    elsif ($elapsed_minutes < 2 * 1440)
    {
        $t->param(show_elapsed_minutes => 1, elapsed_minutes => $elapsed_minutes);
    }
    else
    {
        $t->param(show_elapsed_days => 1, elapsed_days => int($elapsed_minutes / 1440));
    }

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
        binmode(STDOUT, ':raw');
        $t->param(encoding => $enc);
        http_header($http_mime_type, $enc, $cookie);
        print STDOUT $out = Encode::encode($enc, $t->output, Encode::FB_XMLCREF);
    }
    else
    {
        binmode(STDOUT, ':utf8');
        $t->param(encoding => 'UTF-8');
        http_header($http_mime_type, 'utf-8', $cookie);
        print STDOUT $out = $t->output;
    }
    if ($output_file)
    {
        open my $f, '>:utf8', $output_file
            or die "Error opening $output_file: $!";
        print $f $out;
    }
}


sub define_columns
{
    (my $url, my $default_by, my $default_dir, $col_defs) = @_;

    my $s = $settings->{$listview_name};
    $s->{sort_by} = $default_by if !defined $s->{sort_by} || $s->{sort_by} eq '';
    $s->{sort_dir} = $default_dir if !defined $s->{sort_dir} || $s->{sort_dir} eq '';

    for (my $i = 0; $i < @$col_defs; ++$i)
    {
        my $def = $col_defs->[$i];
        my $dir = 0;
        if ($s->{sort_by} eq $i)
        {
            $def->{'sort_' . ($s->{sort_dir} ? 'down' : 'up')} = 1;
            $dir = 1 - $s->{sort_dir};
        }
        $def->{href_sort} = "$url;sort=$i;sort_dir=$dir";
    }

    $t->param(col_defs => $col_defs);
}

# Authorize user, initialize permissions and settings.
sub init_user
{
    $sid = url_param('sid') || '';
    $is_root = 0;
    $can_create_contests = 0;
    $uid = undef;
    $team_name = undef;
    $git_author_name = undef;
    $git_author_email = undef;
    my $bad_sid;
    if ($sid ne '') {
        ($uid, $team_name, my $srole, my $last_ip, my $locked, $git_author_name, $git_author_email, $enc_settings) = $dbh->selectrow_array(q~
            SELECT id, team_name, srole, last_ip, locked, git_author_name, git_author_email, settings FROM accounts WHERE sid = ?~, undef,
            $sid);
        $bad_sid = !defined($uid) || ($last_ip || '') ne CATS::IP::get_ip() || $locked;
        if (!$bad_sid) {
            $is_root = $srole == $cats::srole_root;
            $can_create_contests = $is_root || $srole == $cats::srole_contests_creator;
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
        init_template(param('json') ? 'bad_sid.json.tt' : 'login.html.tt');
        $sid = '';
        $t->param(href_login => url_f('login'));
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
    if ($listview_name)
    {
        my $s = $settings->{$listview_name} ||= {};
        $s->{search} ||= undef;
        defined $s->{$_} or delete $s->{$_} for keys %$s;
    }
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
    $dbi_error = undef;
    $messages //= { map { $_ => init_messages_lang($_) } @cats::langs };
    $t = undef;
    init_user;
    init_contest;
    $listview_name = '';
    $listview_array_name = '';
    $col_defs = undef;
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
    }
    @result;
}


sub problem_status_names()
{+{
    $cats::problem_st_ready     => res_str(700),
    $cats::problem_st_suspended => res_str(701),
    $cats::problem_st_disabled  => res_str(702),
    $cats::problem_st_hidden    => res_str(703),
}}


1;
