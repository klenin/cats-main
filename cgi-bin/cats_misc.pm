package cats_misc;

BEGIN
{
    use Exporter;

    @ISA = qw( Exporter );
    @EXPORT = qw(  
            split_fname
            initialize
            init_template
            init_listview_template
            generate_output
            sql_connect
            sql_disconnect
            http_header
            init_messages
            msg
            url_with_contest
            url
            user_authorize
            templates_path
            escape_html
            order_by
            define_columns
            get_flag
            generate_login
            generate_password
            new_id
            res_str
            attach_listview
            attach_menu
            fatal_error
        );

        
    @EXPORT_OK = qw( $dbh @messages $t $sid $cid $lng $uid $team_name $server_time $contest_title $dbi_error $is_practice
                    $is_root $is_team $is_jury $is_virtual $virtual_diff_time $contest_elapsed_minutes $additional $search);

    %EXPORT_TAGS = ( all => [ @EXPORT, @EXPORT_OK ] );
}

use strict;
use DBD::InterBase;
use HTML::Template;
#use CGI::Fast( ':standard' );
use CGI( ':standard' );
use CGI::Util qw( rearrange unescape escape );
use MIME::Base64;
#use FCGI;

use cats;
use vars qw( $dbh @messages $t $sid $cid $lng $uid $team_name $server_time $contest_title $dbi_error $is_practice );
use vars qw( $is_root $is_team $is_jury $is_virtual $virtual_diff_time $contest_elapsed_minutes);
use vars qw( $listview_name $listview_array_name $col_defs $sort $sort_dir $search $page $visible $additional);


sub split_fname {

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


sub escape_html {

    my $toencode = shift;
    
    $toencode=~s/&/&amp;/g;
    $toencode=~s/\'/&#39;/g;    
    $toencode=~s/\"/&quot;/g;
    $toencode=~s/>/&gt;/g;
    $toencode=~s/</&lt;/g;

    return $toencode;
}


sub http_header {
    
    my $type = shift;
    my $cookie = shift;

    CGI::header(-type => $type, -cookie => $cookie, -charset => 'utf-8');
}


sub sql_connect 
{
    $dbh = DBI->connect($cats::db_dsn, $cats::db_user, $cats::db_password, { AutoCommit => 0, LongReadLen => 1024*1024*8 } );
    
    if (!defined $dbh) 
    {  
        fatal_error('Failed connection to SQL-server');
    }
    

    $dbh->{ HandleError } = sub {

        my $m = "DBI error: ".$_[0] ."\n";
            
        fatal_error($m);

        #$dbi_error .= $m;
        
        0;
    };
}


sub sql_disconnect 
{    
    $dbh->disconnect if ( defined $dbh );
}



sub templates_path
{
    my $template = param( 'iface' ) || '';

    foreach ( @cats::templates )
    {
        if ( $template eq $_->{ 'id' } )
        {
            return $_->{ 'path' };
        }
    }
    
    $cats::templates[0] -> { 'path' };
}



sub init_messages {

    my $msg_file = templates_path()."/.consts";

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
    $search = decode_base64($search);
  
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


sub fatal_error {

    print STDOUT http_header('text/html')."<pre>".escape_html( $_[0] )."</pre>";
    exit( 1 );
}


sub init_template {

    my $file_name = shift;

    my $utf8_encode = sub {
    
        my $text_ref = shift;

        Encode::from_to($$text_ref, 'koi8-r', 'utf-8');
    };
    
    $t = HTML::Template->new( 
        filename => templates_path()."/".$file_name, 
        die_on_bad_params => 0, filter => $utf8_encode, loop_context_vars => 1 );
}



sub init_listview_template {

    $listview_name = shift;
    $listview_array_name = shift;
    my $file_name = shift;
        
    init_listview_params;

    init_template($file_name);
}


sub selected_menu_item {
    
    my $default = shift;
    my $href = shift;

    my $q = new CGI((split('\?', $href))[1]);

    my $page = CGI::url_param('f');

    (defined $page && $q->param('f') eq $page) ||
    (!defined $page && $q->param('f') eq $default);
}


sub mark_selected 
{
    my $default = shift;
    my $menu = shift;

    foreach my $i (@$menu)
    {
        if (selected_menu_item($default, $$i{ href }))
        {
            $$i{ selected } = 1;
            $$i{ dropped } = 1;
        }

        my $submenu = $$i{ submenu };
    
        foreach my $j ( @$submenu )
        {
            if (selected_menu_item($default, $$j{ href }))
            {
                $$j{ selected } = 1;
                $$i{ dropped } = 1;
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


sub res_str {
    $messages[ shift ];
}


sub msg {

    my $id = shift;
    
    $t->param( message => $messages[ $id ] );
}


sub url_with_contest {

    my $url = shift;
    my $contest_id = shift;

#    my $lng = param('lng') || '';
#    my $skin = param('skin') || '';
        
    $url."&sid=$sid&cid=$contest_id";
}


sub url {
    url_with_contest($_[0], $cid);
}


sub attach_listview {
 
    my( $url, $fetch_row, $c, $sort_columns ) = @_;
    my @data = ();
    my $row_count = 0;
    my $start_row = $page * $visible;       

    my $mask = undef;
    for (split(',', $search)) {
	if ($_ =~ /(.*)\=(.*)/) {
	    $mask = {} unless defined $mask;		
	    $mask->{$1} = $2;
        }
    }
    
    while ( my %h = &$fetch_row($c) )
    {            
        my $f = 1;
        if ($search) {                                       
            $f = 0; 
	    if (defined $mask) {
	        $f = 1;
		for (keys %$mask) {
		    if ($h{$_} ne $mask->{$_}) {
			$f = 0;
			last;
		    }
		}
	    }
	    else {
                for ( keys %h  ) {   		

        	    $f = 1 if (defined $h{ $_ } && index( $h{ $_ }, $search ) != -1 );
                }
	    }
        }

        if ($f) {
            if ($row_count >= $start_row && $row_count < $start_row + $visible) 
            {
                push @data, { %h };
            }
            $row_count++;
        }          
	
	last if ($row_count > $cats::max_fetch_row_count);
    };

    my $page_count = int( $row_count / $visible ) + ( $row_count % $visible ? 1 : 0 ) || 1;
 
    my $range_start = $page - $page % $cats::visible_pages;
    $range_start = 0 if ($range_start < 0);

    my $range_end = $range_start + $cats::visible_pages - 1;
    $range_end = $page_count - 1 if ($range_end > $page_count - 1);

    my @pages = ();

    foreach ( $range_start..$range_end )
    {
        push @pages, { 
            page_number => $_ + 1,
            href_page => $url."&page=$_",
            current_page => $_ == $page
        };
    }
 
    
    $t->param( page => $page,
        pages => [@pages],
        search => $search
    );

    my @display_rows = ();

    foreach ( @cats::display_rows )
    {
        push @display_rows, { 
            is_current => ( $visible == $_ ),
            count => $_,
            text => $_
        };
    }
 

    if ($range_start > 0)
    {
        $t->param( href_prev_pages => $url.'&page='.($range_start - 1));
    }

    if ($range_end < $page_count - 1)
    {
        $t->param( href_next_pages => $url.'&page='.($range_end + 1));
    }     

    $t->param( display_rows => [ @display_rows ] );
    $t->param( $listview_array_name => [@data] );
}



sub order_by
{    
   if ($sort ne '' && defined $$col_defs[$sort])
   {
       my $dir = (!$sort_dir) ? 'ASC' : 'DESC';
       return "ORDER BY ".$$col_defs[$sort]{ 'order_by' }." $dir";
   }
   return '';
}


sub generate_output
{

    if (defined $t)
    {
        my $cookie;
        if ($listview_name ne '')
        {
            $cookie = CGI::cookie(-name => $listview_name, 
	                          -value => [$sort, encode_base64($search), $page, $visible, $sort_dir, $additional], 
				  -expires => '+1h');
        }
        $t->param(contest_title => $contest_title);
        $t->param(server_time => $server_time);    
	$t->param(current_team_name => $team_name);
	$t->param(is_virtual => $is_virtual);
	$t->param(virtual_diff_time => $virtual_diff_time);	

	if ($contest_elapsed_minutes < 0)
	{
    	    $t->param(show_remaining_minutes => 1,
		      remaining_minutes => -$contest_elapsed_minutes);
	}
	elsif ($contest_elapsed_minutes / 1440 < 3)
	{
    	    $t->param(show_elapsed_minutes => 1,
		      elapsed_minutes => $contest_elapsed_minutes);
	}
	else
	{
    	    $t->param(show_elapsed_days => 1,
	              elapsed_days => int($contest_elapsed_minutes / 1440));
	}

        if ( defined $dbi_error ) {

            $t->param(dbi_error => $dbi_error);
        }

        print STDOUT http_header('text/html', $cookie);
        print STDOUT $t->output;
    }
}


sub define_columns
{
    my $url = shift;
    my $default = shift;
    my $default_dir = shift;
    $col_defs = shift;

#    $sort = $default if ($sort > length(@$col_defs) or ($sort eq ''));    
    $sort = $default if ($sort eq '');
    $sort_dir = $default_dir if ($sort_dir eq '');

    my $i = 0;
    foreach (@$col_defs)
    {
        my $d = $sort_dir;
        if ($sort eq $i)
        {
           ($sort_dir) ? $$_{ sort_down } = 1 : $$_{ sort_up } = 1;
           $d = int(!$d);
        }
        $$_{ href_sort } = $url."&sort=$i&sort_dir=".$d;
        $i++;
    }
    
    $t->param(col_defs => $col_defs);
}


sub get_flag {

    my $country = shift || return;

    foreach( @cats::countries )
    {
        if ($_->{'id'} eq $country )
        {
            my $flag = defined $_->{'flag'} ? $cats::flags_path."/".$_->{'flag'} : undef;

            return ( $_->{'name'}, $flag );
        }
    }
        
    undef;
}


sub generate_login {    

    my $login_num = undef;
    
    if ( $cats::db_dsn =~ /InterBase/ )
    {
        $login_num = $dbh->selectrow_array('SELECT GEN_ID(login_seq, 1) FROM RDB$DATABASE');
    }
    elsif ( $cats::db_dsn =~ /Oracle/ )
    {
        $login_num = $dbh->selectrow_array(qq~SELECT login_seq.nextval FROM DUAL~);
    }

    return "team#".$login_num if ( $login_num );
}


sub generate_password {
    
    my @ch1 = ( 'e', 'y', 'u', 'i', 'o', 'a' );
    my @ch2 = (  'w', 'r', 't', 'p', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'z', 'x', 'c', 'v', 'b', 'n', 'm' );    

    my $passwd = "";
 
    foreach (1..3)
    {
        $passwd .= @ch1[ rand($#ch1 ) ];    
        $passwd .= @ch2[ rand($#ch2 ) ];
    }
    
    return $passwd;
}


sub new_id {

    if ( $cats::db_dsn =~ /InterBase/ )
    {
        $dbh->selectrow_array('SELECT GEN_ID(key_seq, 1) FROM RDB$DATABASE');
    }
    elsif ( $cats::db_dsn =~ /Oracle/ )
    {
        $dbh->selectrow_array(qq~SELECT key_seq.nextval FROM DUAL~);
    }
    else { undef; }
}


sub user_authorize {

    $sid = url_param('sid') || '';

    $is_root = 0;
    $uid = undef;
    $team_name = undef;
    # авторизация пользователя и установка флага администратора системы
    if ($sid ne '') 
    {
        my $srole;

        ( $uid, $team_name, $srole ) = $dbh->selectrow_array(
            qq~SELECT id, team_name, srole FROM accounts WHERE sid=?~, {}, $sid );
        if ( !defined($uid) )
        {
            init_template("main_bad_sid.htm");
            $sid = '';
            $t->param(href_login => url('main.pl?f=login'));
            generate_output;
            exit(1);
        }
        $is_root = !$srole;
    }

    # получение информации о текущем турнире и установка турнира по-умолчанию
    $cid = url_param('cid') || '';
    if ($cid ne '') 
    {
        my ($contest_exists, $ctype);

        ( $contest_exists, $ctype, $server_time, $contest_title ) = $dbh->selectrow_array(
            qq~SELECT 1, ctype, CATS_EXACT_DATE(CATS_SYSDATE()), title FROM contests WHERE id=?~, {}, $cid );
        unless ($contest_exists)
        {
            fatal_error('invalid contest id');
        }
        $is_practice = ($ctype == 1);
    }
    else
    {
        # тренировочная сессия по умолчанию
        ( $cid, $server_time, $contest_title ) = $dbh->selectrow_array(
            qq~SELECT id, CATS_DATE(CATS_SYSDATE()), title FROM contests WHERE ctype=1~ );
        $is_practice = 1;
    }

    $virtual_diff_time = 0;
    # авторизация пользователя в турнире
    if (defined $uid)
    {
        ($is_team, $is_jury, $is_virtual, $virtual_diff_time) =   
            $dbh->selectrow_array(qq~SELECT 1, is_jury, is_virtual, diff_time FROM contest_accounts WHERE contest_id=? AND account_id=?~, {}, $cid, $uid);

	if (!defined $virtual_diff_time || $virtual_diff_time eq '')
	{
	    $virtual_diff_time = 0;
	}    		

        if (!$is_jury)
        {
		
            my ($start_diff_time, $finish_diff_time) = 
                $dbh->selectrow_array(qq~SELECT CATS_SYSDATE() - $virtual_diff_time - start_date, 
					CATS_SYSDATE() - $virtual_diff_time - finish_date
					FROM contests WHERE id=?~, {}, $cid);
            my $started = ($start_diff_time >= 0);
            my $finished = ($finish_diff_time > 0);
	    
	    # до начала и после окончания тура команда имеет только права гостя
	    if (!$started || $finished)
	    {
		$is_team = 0;
	    }
        }
    }
    else
    {
        $is_jury = 0;
        $is_team = 0;
	$is_virtual = 0;
    }
    
    $contest_elapsed_minutes = $dbh->selectrow_array(
		    qq~SELECT (CATS_SYSDATE() - $virtual_diff_time - start_date)*1440 
	               FROM contests WHERE id=?~, {}, $cid);
		
    $contest_elapsed_minutes = int($contest_elapsed_minutes);       
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

1;
