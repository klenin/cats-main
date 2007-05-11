package CATS::Misc;

BEGIN
{
    use Exporter;

    @ISA = qw(Exporter);
    @EXPORT = qw(
        cats_dir
        split_fname
        initialize
        init_template
        init_listview_template
        generate_output
        http_header
        init_messages
        msg
        url_function
        url_f
        user_authorize
        templates_path
        escape_html
        order_by
        define_columns
        get_flag
        generate_login
        generate_password
        res_str
        attach_listview
        attach_menu
        fatal_error
        state_to_display
        field_by_id
        generate_table
        generate_cmp_query
        generate_count_query
        balance_brackets
        balance_tags
        source_hash
        param_on
    );

    @EXPORT_OK = qw(
        $contest @messages $t $sid $cid $lng $uid $team_name $server_time $contest_title $dbi_error
        $is_root $is_team $is_jury $is_virtual $virtual_diff_time $additional $search $page $visible $init_time);

    %EXPORT_TAGS = (all => [ @EXPORT, @EXPORT_OK ]);
}

use strict;
use warnings;

use HTML::Template;
#use CGI::Fast( ':standard' );
use CGI (':standard');
use Text::Balanced qw(extract_tagged extract_bracketed);
use CGI::Util qw(rearrange unescape escape);
use MIME::Base64;
#use FCGI;
use SQL::Abstract;
use Digest::MD5;
use Time::HiRes;
use Encode;

use CATS::DB;
use CATS::Constants;
use CATS::IP;
use CATS::Diff;
use CATS::Contest;

use vars qw(
    $contest @messages $t $sid $cid $lng $uid $team_name $server_time $contest_title $dbi_error
    $is_root $is_team $is_jury $is_virtual $virtual_diff_time
    $listview_name $listview_array_name $col_defs $sort $sort_dir $search $page $visible $additional
    $request_start_time $init_time
);


my $cats_dir;
sub cats_dir()
{
    $cats_dir ||= $ENV{CATS_DIR} || '/usr/local/apache/CATS/cgi-bin/';
}


sub split_fname
{
    my $path = shift;

    my ($vol, $dir, $fname, $name, $ext);

    my $volRE = '(?:^(?:[a-zA-Z]:|(?:\\\\\\\\|//)[^\\\\/]+[\\\\/][^\\\\/]+)?)' ;    
    my $dirRE = '(?:(?:.*[\\\\/](?:\.\.?$)?)?)' ;
    if ($path =~ m/($volRE)($dirRE)(.*)$/) 
    {
        $vol = $1;
        $dir = $2;
        $fname = $3;
    }

    if ($fname =~ m/^(.*)(\.)(.*)/) 
    {
        $name = $1;
        $ext = $3;
    }
    
    return ($vol, $dir, $fname, $name, $ext);
}


sub escape_html
{
    my $toencode = shift;
    
    $toencode =~ s/&/&amp;/g;
    $toencode =~ s/\'/&#39;/g;
    $toencode =~ s/\"/&quot;/g; #"
    $toencode =~ s/>/&gt;/g;
    $toencode =~ s/</&lt;/g;

    return $toencode;
}


sub escape_xml
{
    my $t = shift;
    
    $t =~ s/&/&amp;/g;
    $t =~ s/>/&gt;/g;
    $t =~ s/</&lt;/g;

    return $t;
}


sub http_header
{
    my ($type, $encoding, $cookie) = @_;

    CGI::header(-type => $type, -cookie => $cookie, -charset => $encoding);
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
    my $msg_file = templates_path() . "/consts";

    my $r = open FILE, "<".$msg_file;
   
    unless ( $r ) { 
        fatal_error ( "Couldn't open message file: '$msg_file'."); 
    }
     
    binmode(FILE, ':raw');    
       
    while( <FILE> )
    {
        Encode::from_to($_, 'koi8-r', 'utf-8');

        $messages[$1] = $2 if ( $_ =~ m/(^\d*)\s*\"(.*)\"/ );
    }

    close FILE;

    1;
}


sub init_listview_params
{
    ($sort, $search, $page, $visible, $sort_dir, $additional) = CGI::cookie($listview_name);
    $search = decode_base64($search || '');

    $page = url_param('page') if (defined url_param('page'));

    if (defined param('filter'))
    {
        $search = param('search');
        $page = 0;
    }

    if (defined url_param('sort'))
    {
        $sort = url_param('sort');
        $page = 0;
    }
    
    if (defined url_param('sort_dir'))
    {
	$sort_dir = url_param('sort_dir');
	$page = 0;
    }	
    
    if (defined param('visible'))
    {
        $visible = param('display_rows');
        $page = 0;
    }
    $visible = $cats::display_rows[0] if (!$visible);

#    $sort = int($sort);
#    $sort_dir = int($sort_dir);
#    $sort = $sort || '';
#    $sort_dir = $sort_dir || '';
}


sub fatal_error
{
    print STDOUT http_header('text/html', 'utf-8') . '<pre>' . escape_html( $_[0] ) . '</pre>';
    exit(1);
}


#my $template_file;
sub init_template
{
    my $file_name = shift;
    #if (defined $t && $template_file eq $file_name) { $t->param(tf=>1); return; }

    my $utf8_encode = sub
    {
        my $text_ref = shift;

        #Encode::from_to($$text_ref, 'koi8-r', 'utf-8');
        $$text_ref = Encode::decode('koi8-r', $$text_ref);
    };
    #$template_file = $file_name;
    $t = HTML::Template->new(
        filename => templates_path() . "/$file_name", cache => 1,
        die_on_bad_params => 0, filter => $utf8_encode, loop_context_vars => 1);
}


sub init_listview_template
{
    $listview_name = shift;
    $listview_array_name = shift;
    my $file_name = shift;

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

    my $page = CGI::url_param('f');
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


sub gen_url_params
{
    my (%p) = @_;
    map { defined $p{$_} ? "$_=$p{$_}" : () } keys %p;
}


sub url_function
{
  my ($f, %p) = @_;
  join '&', "main.pl?f=$f", gen_url_params(%p);
}


sub url_f
{
    url_function(@_, sid => $sid, cid => $cid);
}


sub attach_listview
{
    my ($url, $fetch_row, $c, $sort_columns, $p) = @_;
    my @data = ();
    my $row_count = 0;
    my $start_row = ($page || 0) * ($visible || 0);
    my $pp = $p->{page_params} || {};
    my $page_extra_params = join '', map "\&$_=$pp->{$_}", keys %$pp;

    my $mask = undef;
    for (split(',', $search))
    {
        if ($_ =~ /(.*)\=(.*)/)
        {
            $mask = {} unless defined $mask;
            $mask->{$1} = $2;
        }
    }

    while (my %h = &$fetch_row($c))
    {
        my $f = 1;
        if ($search)
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
                for (keys %h)
                {
                    $f = 1 if defined $h{$_} && index($h{$_}, $search) != -1;
                }
            }
        }

        if ($f)
        {
            if ($row_count >= $start_row && $row_count < $start_row + $visible)
            {
                push @data, { %h, odd => $row_count % 2 };
            }
            $row_count++;
        }
	
	    last if $row_count > $cats::max_fetch_row_count;
    }

    my $page_count = int($row_count / $visible) + ($row_count % $visible ? 1 : 0) || 1;

    $page ||= 0;
    my $range_start = $page - $page % $cats::visible_pages;
    $range_start = 0 if ($range_start < 0);

    my $range_end = $range_start + $cats::visible_pages - 1;
    $range_end = $page_count - 1 if ($range_end > $page_count - 1);

    my @pages = map {{
        page_number => $_ + 1,
        href_page => "$url&page=$_$page_extra_params",
        current_page => $_ == $page
    }} ($range_start..$range_end);

    $t->param(
        page => $page,
        pages => [@pages],
        search => $search
    );

    my @display_rows = ();

    for (@cats::display_rows)
    {
        push @display_rows, { 
            is_current => ($visible == $_),
            count => $_,
            text => $_
        };
    }

    if ($range_start > 0)
    {
        $t->param( href_prev_pages => "$url$page_extra_params&page=" . ($range_start - 1));
    }

    if ($range_end < $page_count - 1)
    {
        $t->param( href_next_pages => "$url$page_extra_params&page=" . ($range_end + 1));
    }     

    $t->param(display_rows => [ @display_rows ]);
    $t->param($listview_array_name => [@data]);
}


sub order_by
{
   if ($sort ne '' && defined $col_defs->[$sort])
   {
       my $dir = $sort_dir ? 'DESC' : 'ASC';
       return 'ORDER BY ' . $col_defs->[$sort]{order_by} . " $dir";
   }
   return '';
}


sub generate_output
{
    my ($output_file) = @_;
    defined $t or return;
    my $cookie;
    if ($listview_name ne '')
    {
        my @values = map { $_ || '' }
           ($sort, encode_base64($search), $page, $visible, $sort_dir, $additional);
        $cookie = CGI::cookie(
            -name => $listview_name, -value => [@values], -expires => '+1h');
    }
    $t->param(
        contest_title => $contest_title,
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

    $t->param(request_process_time => sprintf '%.3fs',
        Time::HiRes::tv_interval($request_start_time, [ Time::HiRes::gettimeofday ]));
    $t->param(init_time => sprintf '%.3fs', $init_time);
    my $out = '';
    if (my $enc = param('enc'))
    {
        binmode(STDOUT, ':raw');
        $t->param(encoding => $enc);
        print STDOUT http_header('text/html', $enc, $cookie);
        print STDOUT $out = Encode::encode($enc, $t->output, Encode::FB_XMLCREF);
    }
    else
    {
        binmode(STDOUT, ':utf8');
        $t->param(encoding => 'utf-8');
        print STDOUT http_header('text/html', 'utf-8', $cookie);
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
    my $url = shift;
    my $default = shift;
    my $default_dir = shift;
    $col_defs = shift;

#    $sort = $default if ($sort > length(@$col_defs) or ($sort eq ''));    
    $sort = $default if (!defined $sort || $sort eq '');
    $sort_dir = $default_dir if (!defined $sort_dir || $sort_dir eq '');

    my $i = 0;
    for (@$col_defs)
    {
        my $d = $sort_dir;
        if ($sort eq $i)
        {
           ($sort_dir) ? $$_{ sort_down } = 1 : $$_{ sort_up } = 1;
           $d = int(!$d);
        }
        $$_{ href_sort } = $url . "&sort=$i&sort_dir=".$d;
        $i++;
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


sub generate_login
{
    my $login_num;

    if ($CATS::Connect::db_dsn =~ /InterBase/)
    {
        $login_num = $dbh->selectrow_array('SELECT GEN_ID(login_seq, 1) FROM RDB$DATABASE');
    }
    elsif ($cats_db::db_dsn =~ /Oracle/)
    {
        $login_num = $dbh->selectrow_array(qq~SELECT login_seq.nextval FROM DUAL~);
    }

    return "team#$login_num" if $login_num;
}


sub generate_password
{
    my @ch1 = ('e', 'y', 'u', 'i', 'o', 'a');
    my @ch2 = ('w', 'r', 't', 'p', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'z', 'x', 'c', 'v', 'b', 'n', 'm');

    my $passwd = '';

    for (1..3)
    {
        $passwd .= @ch1[rand(@ch1)];
        $passwd .= @ch2[rand(@ch2)];
    }

    return $passwd;
}


sub user_authorize
{
    $sid = url_param('sid') || '';
    $is_root = 0;
    $uid = undef;
    $team_name = undef;
    # авторизация пользователя и установка флага администратора системы
    if ($sid ne '')
    {
        my $srole;

        ($uid, $team_name, $srole, my $last_ip) = $dbh->selectrow_array(qq~
            SELECT id, team_name, srole, last_ip FROM accounts WHERE sid = ?~, {}, $sid);
        if (!defined($uid) || $last_ip ne CATS::IP::get_ip())
        {
            init_template('main_bad_sid.htm');
            $sid = '';
            $t->param(href_login => url_f('login'));
            generate_output;
            exit(1);
        }
        $is_root = !$srole;
    }

    # получение информации о текущем турнире и установка турнира по умолчанию
    $cid = url_param('cid') || '';
    if ($contest && ref $contest ne 'CATS::Contest') {
        warn "Strange contest: $contest";
        undef $contest;
    }
    $contest ||= CATS::Contest->new;
    $contest->load($cid);
    $contest_title = $contest->{title};
    $server_time = $contest->{server_time};
    #($server_time) = $dbh->selectrow_array(q~SELECT CATS_DATE(CATS_SYSDATE()) FROM RDB$DATABASE~);
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

        # до начала тура команда имеет только права гостя
        $is_team &&= $is_jury || $contest->has_started($virtual_diff_time);
    }
}


sub initialize
{
    $dbi_error = undef;
    init_messages;
    user_authorize;
    $t = undef;
    $listview_name = '';
    $listview_array_name = '';
    $col_defs = undef;
}


sub state_to_display
{
    my ($state) = @_;
    (
        not_processed =>         $state == $cats::st_not_processed,
        unhandled_error =>       $state == $cats::st_unhandled_error,
        install_processing =>    $state == $cats::st_install_processing,
        testing =>               $state == $cats::st_testing,
        accepted =>              $state == $cats::st_accepted,
        wrong_answer =>          $state == $cats::st_wrong_answer,
        presentation_error =>    $state == $cats::st_presentation_error,
        time_limit_exceeded =>   $state == $cats::st_time_limit_exceeded,                                
        memory_limit_exceeded => $state == $cats::st_memory_limit_exceeded,
        runtime_error =>         $state == $cats::st_runtime_error,
        compilation_error =>     $state == $cats::st_compilation_error,
        security_violation =>    $state == $cats::st_security_violation
    );
}


# записи
sub field_by_id
{
    my ($id, $table, $field) = @_;
    my $c = $dbh->prepare(qq~SELECT $field FROM $table WHERE id=?~);
    $c->execute($id);
    my ($title) = $c->fetchrow_array;
    $title;
}


# создаем таблички результатов сравнения программ
# Предполагается, что уже создан массив @titles заголовков и хеш %srcfiles имён tmp-файлов
sub generate_table
{
    my ($titles_ref, $srcfiles_ref, $pid, $limit) = @_;
    my @titles = @$titles_ref;
    my %srcfiles = %$srcfiles_ref;

    my @rows;
    my $deleted;
    while (@titles)
    {
        my $rid1 = $titles[0]{rid};
        my $team1 = $titles[0]{id};
        my %cur_row = (id =>  $team1);
        my @cells;
        if (!$limit)
        {
            push @cells, undef foreach (1..$deleted);
        }
        
        foreach (@titles)
        {
            my $rid2 = $$_{rid};
            my $value = CATS::Diff::cmp_diff($srcfiles{$rid1},$srcfiles{$rid2});            #CATS::Diff::cmp_advanced($srcfiles{$title1},$srcfiles{$title2});
            my %cell = (
                value => $value,
                href => url_f('cmp', rid1 => $rid1, rid2 => $rid2, pid => $pid),
                diff_href => url_f('diff_runs', r1 => $rid1, r2 => $rid2),
                team1 => $team1,
                team2 => $$_{id}
            );          
            
            $cell{value}>=80 and $cell{alert}=1;
            push @cells, \%cell if (!$limit || $value>=$limit);
        }
        %cur_row = (%cur_row, cells => \@cells);                
        push @rows, \%cur_row;
        `del $srcfiles{$rid1}`;
        shift @titles;
        $deleted++;
    }
    
    @rows;
}


# формирует запрос для построения таблицы выбора задачи, вместе с размером
# выходной таблицы
sub generate_count_query
{
    my ($contest, $teams, $vers) = @_;

    my $query =
        q~SELECT
            P.id,
            P.title,~;
    $contest ne 'all' and
    $query .=q~             C.id,
            C.title,~
    or $query .= 'NULL, NULL,';
    
    $contest == 500001 and $query .= 'NULL '
    or $query .= '('.generate_cmp_query($contest, $teams, $vers,1).')';
    
    $query .=
        q~FROM
            problems P,
            contests C,
            contest_problems CP
        WHERE
            CP.problem_id = P.id and
            CP.contest_id = C.id ~;
    !$contest || $contest ne 'all' and $query .= "AND C.id = $contest ";
    $query .= q~GROUP BY C.id, P.id, P.title, C.title ~;
    $query;    
}


# формирование запроса на сравнение
sub generate_cmp_query
{
    my ($contest, $teams, $vers, $count) = @_;
        
    my $query = 'SELECT ';
    if (defined ($count))
    {
        $query .= 'count(';
        $vers eq 'last' || !$vers and $query .= 'DISTINCT ';
        $query .= 'A.id) ';
    }
    else
    {
        $query .= 'A.team_name, A.id, ';
        $vers eq 'all' and $query .= 'R.id ' or $query .='max(R.id) '; # все версии или только последние
    }
    
    $query .= q~FROM ACCOUNTS A, SOURCES  S, REQS    R ~;
    
    ($teams eq 'all' or $contest eq 'all') and $query .= 'WHERE ' or
    $query .= q~, CONTEST_ACCOUNTS CA  WHERE CA.account_id = A.id AND ~ and
    (!$teams || $teams eq 'incontest') and                 # только команды-участники
    $query .=q~ CA.is_ooc=0 AND CA.is_remote=0 AND ~ or
    $teams eq 'ooc' and
    $query .=q~ CA.is_ooc=1 AND CA.is_remote=1 AND ~;         # только команды ooc

    $count and $query .= 'R.problem_id = P.id AND ' or $query .= 'R.problem_id = ? AND ';
    $query .=q~ R.account_id = A.id AND S.req_id = R.id AND S.de_id in (7,102,3016) AND R.state <> ~.$cats::st_compilation_error ;
    $contest ne 'all' and $query .= " AND R.contest_id = ".$contest;
    $vers ne 'all' && !defined($count) and $query .=' GROUP BY A.team_name, A.id';
    !$count and $query .= " ORDER BY A.team_name";

    $query;
}


sub balance_brackets
{
    my $text = shift;
    my @extr = extract_bracketed ($text, '()');
    $extr[0];
}


sub balance_tags
{
    my ($text, $tag1, $tag2) = @_;
    my @extr = extract_tagged ($text, $tag1, $tag2, undef);
    $extr[0];
}


sub source_hash
{
    Digest::MD5::md5_hex(Encode::encode_utf8($_[0]));
}


sub param_on
{
    return (param($_[0]) || '') eq 'on';
}


1;
