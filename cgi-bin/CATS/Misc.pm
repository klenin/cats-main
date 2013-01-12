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
        init_template
        init_listview_template
        generate_output
        http_header
        msg
        url_f
        templates_path
        order_by
        define_columns
        get_flag
        res_str
        attach_listview
        attach_menu
        save_settings
    );

    @EXPORT_OK = qw(
        $contest $t $sid $cid $uid $server_time
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
    $contest $t $sid $cid $uid $team_name $server_time $dbi_error
    $is_root $is_team $is_jury $can_create_contests $is_virtual $virtual_diff_time
    $listview_name $col_defs $request_start_time $init_time $settings $enc_settings
);

my ($listview_array_name, @messages, $http_mime_type, %extra_headers);

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


sub init_messages
{
    return if @messages;
    my $msg_file = templates_path() . '/consts';

    open my $f, '<', $msg_file or
        die "Couldn't open message file: '$msg_file'.";
    binmode($f, ':utf8');
    while (<$f>) {
        m/^(\d+)\s+\"(.*)\"\s*$/ or next;
        $messages[$1] and die "Duplicate message id: $1";
        $messages[$1] = $2;
    }
    close $f;
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

    $s->{rows} ||= $cats::display_rows[0];
    my $rows = param('rows') || 0;
    if ($rows > 0) {
        $s->{page} = 0 if $s->{rows} != $rows;
        $s->{rows} = $rows;
    }
}


#my $template_file;
sub init_template
{
    my ($file_name) = @_;
    #if (defined $t && $template_file eq $file_name) { $t->param(tf=>1); return; }

    my %ext_to_mime = (
        htm => 'text/html',
        html => 'text/html',
        xml => 'application/xml',
        ics => 'text/calendar',
        json => 'application/json',
    );
    while (my ($ext, $mime) = each %ext_to_mime)
    {
        $file_name =~ /\.$ext(\.tt)?$/ or next;
        $http_mime_type = $mime;
        last;
    }
    $http_mime_type or die 'Unknown template extension';
    %extra_headers = ();
    %extra_headers = ('Content-Disposition' => 'inline;filename=contests.ics') if $file_name =~ /\.ics$/;
    #$template_file = $file_name;
    $t = CATS::Template->new($file_name, cats_dir());
;}


sub init_listview_template
{
    ($listview_name, $listview_array_name, my $file_name) = @_;

    init_listview_params;

    init_template($file_name);
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
    my $t = $messages[shift];
    sprintf($t, @_);
}


sub msg
{
    $t->param(message => res_str(@_));
}


sub url_f
{
    CATS::Utils::url_function(@_, sid => $sid, cid => $cid);
}


sub attach_listview
{
    my ($url, $fetch_row, $sth, $p) = @_;
    my @data = ();
    my $row_count = 0;
    $listview_name or die;
    my $s = $settings->{$listview_name};
    my $page = \$s->{page};
    my $start_row = ($$page || 0) * ($s->{rows} || 0);
    my $pp = $p->{page_params} || {};
    my $page_extra_params = join '', map ";$_=$pp->{$_}", keys %$pp;

    my $mask = undef;
    for (split(',', $s->{search}))
    {
        if ($_ =~ /(.*)\=(.*)/)
        {
            $mask = {} unless defined $mask;
            $mask->{$1} = $2;
        }
    }

    while (my %h = &$fetch_row($sth))
    {
	    last if $row_count > $cats::max_fetch_row_count;
        my $f = 1;
        if ($s->{search})
        {
            $f = 0;
            if (defined $mask)
            {
                $f = 1;
                for (keys %$mask)
                {
                    if (($h{$_} || '') ne ($mask->{$_} || ''))
                    {
                        $f = 0;
                        last;
                    }
                }
	        }
            else
            {
                my $rx = qr/\Q$s->{search}\E/i;
                for (values %h)
                {
                    $f = 1 if defined $_ && Encode::decode_utf8($_) =~ $rx;
                }
            }
        }

        if ($f)
        {
            if ($row_count >= $start_row && $row_count < $start_row + $s->{rows})
            {
                push @data, { %h, odd => $row_count % 2 };
            }
            $row_count++;
        }

    }

    my $rows = $s->{rows} || 1;
    my $page_count = int($row_count / $rows) + ($row_count % $rows ? 1 : 0) || 1;

    $$page ||= 0;
    my $range_start = $$page - $$page % $cats::visible_pages;
    $range_start = 0 if ($range_start < 0);

    my $range_end = $range_start + $cats::visible_pages - 1;
    $range_end = $page_count - 1 if ($range_end > $page_count - 1);

    my @pages = map {{
        page_number => $_ + 1,
        href_page => "$url;page=$_$page_extra_params",
        current_page => $_ == $$page
    }} ($range_start..$range_end);

    $t->param(page => $$page, pages => \@pages, search => $s->{search});

    my @display_rows = ();

    for (@cats::display_rows)
    {
        push @display_rows, {
            is_current => ($s->{rows} == $_),
            count => $_,
            text => $_
        };
    }

    if ($range_start > 0)
    {
        $t->param( href_prev_pages => "$url$page_extra_params;page=" . ($range_start - 1));
    }

    if ($range_end < $page_count - 1)
    {
        $t->param( href_next_pages => "$url$page_extra_params;page=" . ($range_end + 1));
    }

    $t->param(display_rows => [ @display_rows ]);
    $t->param($listview_array_name => [@data]);
}


sub order_by
{
    my $s = $settings->{$listview_name};
    defined $s->{sort_by} && $s->{sort_by} =~ /^\d+$/ && $col_defs->[$s->{sort_by}]
        or return '';
    sprintf 'ORDER BY %s %s',
        $col_defs->[$s->{sort_by}]{order_by}, ($s->{sort_dir} ? 'DESC' : 'ASC');
}


sub generate_output
{
    my ($output_file) = @_;
    defined $t or return;
    $contest->{time_since_start} or warn 'No contest from: ', $ENV{HTTP_REFERER} || '';
    $t->param(
        contest_title => $contest->{title},
        server_time => $server_time,
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
    my $cookie = $uid ? undef : cookie(
        -name => 'settings', -value => encode_base64($enc_settings), -expires => '+1h');
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


sub get_flag
{
    my $country_id = shift || return;
    my ($country) = grep { $_->{id} eq $country_id } @cats::countries;
    $country or return;
    my $flag = defined $country->{flag} ? "$cats::flags_path/$country->{flag}" : undef;
    return ($country->{name}, $flag);
}


# авторизация пользователя, установка прав и настроек
sub init_user
{
    $sid = url_param('sid') || '';
    $is_root = 0;
    $can_create_contests = 0;
    $uid = undef;
    $team_name = undef;
    if ($sid ne '')
    {
        ($uid, $team_name, my $srole, my $last_ip, $enc_settings) = $dbh->selectrow_array(qq~
            SELECT id, team_name, srole, last_ip, settings FROM accounts WHERE sid = ?~, {}, $sid);
        if (!defined($uid) || ($last_ip || '') ne CATS::IP::get_ip())
        {
            init_template('bad_sid.' . (param('json') ? 'json' : 'html') . '.tt');
            $sid = '';
            $t->param(href_login => url_f('login'));
        }
        else
        {
            $is_root = $srole == $cats::srole_root;
            $can_create_contests = $is_root || $srole == $cats::srole_contests_creator;
        }
    }
    if (!$uid)
    {
        $enc_settings = cookie('settings') || '';
        $enc_settings = decode_base64($enc_settings) if $enc_settings;
    }
    # При возникновении любых проблем сбрасываем настройки
    $settings = eval { $enc_settings && Storable::thaw($enc_settings) } || {};
}

sub extract_cid_from_cpid
{
    my $cpid = url_param('cpid') or return;
    return $dbh->selectrow_array(qq~
        SELECT contest_id FROM contest_problems WHERE id = ?~, undef,
        $cpid);
}

# получение информации о текущем турнире и установка турнира по умолчанию
sub init_contest
{
    $cid = url_param('cid') || param('clist') || extract_cid_from_cpid || '';
    $cid =~ s/^(\d+).*$/$1/; # берём первый турнир из clist
    if ($contest && ref $contest ne 'CATS::Contest') {
        use Data::Dumper;
        warn "Strange contest: $contest from ", $ENV{HTTP_REFERER} || '';
        warn Dumper($contest);
        undef $contest;
    }
    $contest ||= CATS::Contest->new;
    $contest->load($cid);
    $server_time = $contest->{server_time};
    $cid = $contest->{id};

    $virtual_diff_time = 0;
    # авторизация пользователя в турнире
    $is_jury = 0;
    $is_team = 0;
    $is_virtual = 0;
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
        # При попытке просмотреть скрытый турнир показываем вместо него тренировочный
        $contest->load(0);
        $server_time = $contest->{server_time};
        $cid = $contest->{id};
    }
    # до начала тура команда имеет только права гостя
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
    init_messages;
    $t = undef;
    init_user;
    init_contest;
    $listview_name = '';
    $listview_array_name = '';
    $col_defs = undef;
}


1;
