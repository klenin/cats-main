sub cmp_output_problem
{
    init_template('main_cmp_out.htm');

    my @submenu = ( { href_item => url('main.pl?f=cmp&setparams=1'), item_name => res_str(546)} );
    $t->param(submenu => [ @submenu ] );    

# ÅßÊÕ ÌÅ ÁØÀÏŞÌŞ ÃŞÄŞÂŞ
    my $problem_id = param("problem_id");
    if (! defined ($problem_id))
    {
        $t->param(noproblems => 1);
	return;
    }

# ÑÃÌŞÅË ÌŞÃÁŞÌÕÅ ÃŞÄŞÂÕ Õ ÉÊŞÄTË ÅÖÍ Á ÃŞÖÍÊÍÁÍÉ ßĞÏŞÌÕÂÉÕ
    $t->param(problem_title => field_by_id($problem_id, 'PROBLEMS', 'title'));
    
# ÍĞÎÏŞÁÊÚÅË ÃŞÎÏÍß

# ÂÕĞŞÅË ÉÑÉÕßØ Õ Á ÃŞÁÕßÕËÍßĞÕ ÍĞ ÌÕÓ ßĞŞÁÕË ÄÍÎÍÊÌÕĞÅÊİÌØÅ ÑßÊÍÁÕÚ
  
    my $cont = (CGI::cookie('contest') or url_param('cid'));
    my $query = generate_cmp_query ($cont, CGI::cookie ('versions'), CGI::cookie ('teams'));
    my $c = $dbh->prepare ($query.order_by);
    $c->execute($problem_id);	
	
    my ($tname, $tid, $stime) = $c->fetchrow_array;
	
# ÅßÊÕ ÌŞ ÃŞÎÏÍß ÌÕÂÅÖÍ ÌÅ ÌŞÈÄÅÌÍ
    if (! defined($tname))
    {
    	$t->param(norecords => 1);
	return;
    }

# ÒÍÏËÕÏÍÁŞÌÕÅ ÃŞÖÍÊÍÁÉÍÁ ĞŞÀÊÕÆØ
    my @titles;		#ÃÄÅßİ ÓÏŞÌÕĞİ ÃŞÖÍÊÍÁÉÕ ĞŞÀÊÕÆØ
    while ($tname)
    {
        my $cc = $dbh->prepare('SELECT is_ooc, is_remote FROM contest_accounts WHERE account_id=? AND contest_id=?');
    	$cc->execute($tid, CGI::cookie('contest'));
        my ($is_ooc, $is_remote) = $cc->fetchrow_array;
        $cc->finish;
        my %col_title = (id => $tname,
                         time => $stime,
                         href => url("main.pl?f=cmp&tid=$tid&pid=$problem_id"));
        $is_ooc and %col_title = (%col_title, ooc=>1);
        $is_remote and %col_title = (%col_title, remote=>1);
	push @titles, \%col_title;
	($tname, $tid, $stime) = $c->fetchrow_array;
    }
    $c->finish;	

    my %srcfiles;
    my %reqid;
    $dbh->{LongReadLen} = 16384;        ### 16Kb BLOB-ÎÍÊÚ
    foreach (@titles)
    {	
	$c = $dbh->prepare(q~
            SELECT
		S.src,
                R.id
            FROM
		SOURCES S,
		REQS	R,
		ACCOUNTS	A
	    WHERE
		A.team_name = ? AND
		R.account_id = A.id AND
		S.req_id = R.id
			~);
	$c->execute($$_{id});
	my ($src, $rid) = $c->fetchrow_array;
	$srcfiles{$$_{id}} = cats_diff::prepare_src ($src);
        $reqid{$$_{id}} = $rid;
	$c->finish;
    }

# ßÍÃÄŞÅË ßÍÀßĞÁÅÌÌÍ ĞŞÀÊÕÂÉÑ
    $t->param(col_titles => \@titles);
    my @rows = generate_table (\@titles, \%srcfiles, \%reqid, $problem_id);
    $t->param(row => \@rows);
    1;	
}

sub cmp_output_team
{
    init_template('main_cmp_out.htm');

    my @submenu = ( { href_item => url('main.pl?f=cmp&setparams=1'), item_name => res_str(546)} );
    $t->param(submenu => [ @submenu ] );    

    $t->param(team_stat => 1);

# ÑÃÌŞÅË ÌŞÃÁŞÌÕÅ ÃŞÄŞÂÕ Õ ÉÊŞÄTË ÅÖÍ Á ÃŞÖÍÊÍÁÍÉ ßĞÏŞÌÕÂÉÕ
    $t->param(problem_title => field_by_id(param("pid"), 'PROBLEMS', 'title'));
# ÑÃÌŞÅË ÌŞÃÁŞÌÕÅ ÉÍËŞÌÄØ Õ ÉÊŞÄTË ÅÖÍ ĞÍÔÅ Á ÃŞÖÍÊÍÁÍÉ ßĞÏŞÌÕÂÉÕ
    $t->param(team_name => field_by_id(param("tid"), 'ACCOUNTS', 'team_name'));

    $dbh->{LongReadLen} = 16384;        ### 16Kb BLOB-ÎÍÊÚ
    my $c = $dbh->prepare(q~
        SELECT
            S.src,
            R.submit_time,
            R.id
        FROM
            SOURCES S,
            REQS R
        WHERE
            R.account_id = ? AND
            R.problem_id = ? AND
            S.req_id = R.id
                          ~);
    $c->execute(param("tid"), param("pid"));
    my ($src, $stime, $rid) = $c->fetchrow_array;
    my @titles;
    my %srcfiles;
    my %reqid;
    while ($stime)
    {
        my %col_title = (id => $stime);
        push @titles, \%col_title;
	$srcfiles{$stime} = cats_diff::prepare_src ($src);
        $reqid{$stime} = $rid;
        ($src, $stime, $rid) = $c->fetchrow_array;
    }

    my @rows = generate_table (\@titles, \%srcfiles, \%reqid, param('pid'));
    $t->param(row => \@rows);
    $t->param(col_titles => \@titles);
   
    1;
}

sub cmp_show_sources
{
    init_template("main_cmp_source.htm");
    
    $t->param(problem_title => field_by_id(param("pid"), 'PROBLEMS', 'title'));
    
    my $c = $dbh->prepare(q~
        SELECT
            A.team_name,
            S.src
        FROM
            ACCOUNTS A,
            SOURCES S,
            REQS R
        WHERE
            R.id = ? AND
            A.id = R.account_id AND
            S.req_id = R.id                
                          ~);

    my @teams_rid = (param("rid1"), param("rid2"));
    my @team;
    my @src;
    foreach (@teams_rid)
    {
        $c->execute($_);
        my ($tname, $tsrc) = $c->fetchrow_array;
        push @team, $tname;
        push @src, $tsrc;
        $c->finish;
    }
    
    $t->param(team1 => $team[0]);
    $t->param(team2 => $team[1]);
    $t->param(source1 => prepare_src_show($src[0]));
    $t->param(source2 => prepare_src_show($src[1]));
}

sub cmp_set_params
{
    my $backlink = shift;
    init_template("main_cmp_param.htm");
    $t->param(backlink => $backlink);
    
    my $cookie;
    $cookie = CGI::cookie('teams') or $cookie = 'incontest';
    $t->param('teams_'.$cookie => 1);
    $t->param('init_team' => $cookie);
    
    $cookie = CGI::cookie('versions') or $cookie = 'last';
    $t->param('view_'.$cookie => 1);
    $t->param('init_vers' => $cookie);
    
    $cookie = CGI::cookie('contest') or $cookie = param('cid');
    $t->param(init_cont => $cookie);
    $t->param(cur_cid => param('cid'));
    my $c = $dbh->prepare(q~SELECT id, title FROM contests ORDER BY title ~);
    $c->execute;
    my ($cid, $title) = $c->fetchrow_array;
    my @contests;
    while ($cid)
    {
        my %rec = (cid=>$cid, title=>$title);
        $cid == $cookie and %rec = (%rec, sel=>1);
        push @contests, \%rec;
        ($cid, $title) = $c->fetchrow_array;
    }
    $t->param(contest_all=>1) if $cookie=='all';
    $t->param(contests => \@contests);
    
    1;
}

sub cmp_frame
{       
    if (defined param("showtable") & $is_jury)
    {
	cmp_output_problem;
	return;
    }
    
    if (defined param("tid") & $is_jury)
    {
        cmp_output_team;
        return;
    }
    
    if (defined param("rid1") & $is_jury)
    {
        cmp_show_sources;
        return;
    }
    
    if (defined param("setparams") & $is_jury)
    {
        cmp_set_params(url('main.pl?f=cmp'));
        return;
    }

    init_listview_template( "problems$cid" . ($uid || ''), 'problems', 'main_cmp.htm' );

      my @cols = 
              ( { caption => res_str(602), order_by => '3', width => '30%' },
                ($is_practice ? { caption => res_str(603), order_by => '4', width => '30%' } : ()),
                { caption => res_str(604), order_by => '5', width => '5%' },
                { caption => res_str(605), order_by => '6', width => '5%' },
                { caption => res_str(606), order_by => '7', width => '5%' } );

    define_columns(url('main.pl?f=cmp'), 0, 0, [ @cols ]);
       
    my $c;
    if ($is_practice)
    {
        $c = $dbh->prepare(qq~
            SELECT CP.id, P.id, P.title, OC.title,
              (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_accepted), 
              (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_wrong_answer), 
              (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_time_limit_exceeded)
            FROM problems P, contests C, contest_problems CP, contests OC
            WHERE CP.contest_id=C.id AND CP.problem_id=P.id AND C.id=? AND OC.id=P.contest_id 
            ~.order_by);
        $c->execute($cid);
    }
    else
    {
        $c = $dbh->prepare(qq~
            SELECT CP.id, P.id, CP.code||' - '||P.title, NULL,
              (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_accepted AND D.account_id = ?),
              (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_wrong_answer AND D.account_id = ?), 
              (SELECT COUNT(*) FROM reqs D WHERE D.problem_id = P.id AND D.state = $cats::st_time_limit_exceeded AND D.account_id = ?)
              FROM problems P, contest_problems CP
              WHERE CP.contest_id=? AND CP.problem_id=P.id 
              ~.order_by);
        my $aid = $uid || 0; # íà ñëó÷àé àíîíèìíîãî ïîëüçîâàòåëÿ
        # îïÿòü áàã ñ ïîğÿäêîì ïàğàìåòğîâ
        $c->execute($cid, $aid, $aid, $aid);
    }


    my $fetch_record = sub($)
    {            
        if ( my( $cpid, $pid, $problem_name, $contest_name, $accept_count, $wa_count, $tle_count ) = $_[0]->fetchrow_array)
        {       
            return ( 
                is_practice => $is_practice,
                editable => $is_jury,
                is_team => $is_team || $is_practice,
                problem_id => $pid,
                problem_name => $problem_name, 
                href_view_problem => url("main.pl?f=problem_text&pid=$pid"),
                contest_name => $contest_name,
                accept_count => $accept_count,
                wa_count => $wa_count,
                tle_count => $tle_count
            );
        }   

        return ();
    };
            
    attach_listview(url('main.pl?f=cmp'), $fetch_record, $c);

    $c->finish;

    $c = $dbh->prepare(qq~SELECT id, description FROM default_de WHERE in_contests=1 ORDER BY code~);
    $c->execute;

    my @de;
    push ( @de, { de_id => "by_extension", de_name => res_str(536) } );

    while ( my ( $de_id, $de_name ) = $c->fetchrow_array )
    {
        push ( @de, { de_id => $de_id, de_name => $de_name  } );
    }    

    $c->finish;
    $t->param(is_team => ($is_team || $is_practice), is_practice => $is_practice, de_list => [ @de ]);

	my @submenu = ( { href_item => url('main.pl?f=cmp&setparams=1'), item_name => res_str(546)} );
    $t->param(submenu => [ @submenu ] );    
}
