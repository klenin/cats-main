#!/usr/bin/perl -w
use cats;
use cats_misc qw(:all);
use DBD::InterBase;
use HTML::Template;


sub sql_connect 
{
    $dbh = DBI->connect($cats::db_dsn, $cats::db_user, $cats::db_passwd, { AutoCommit => 0, LongReadLen => 1024*1024 } );
    $dbh->{ HandleError } = sub {

        print "DBI error: ".$_[0] ."\n";
        exit(0);   
    };

}


sub sql_disconnect 
{    
    $dbh->disconnect if ( defined $dbh );
}


sql_connect;



#my $c = $dbh->prepare(
# qq~SELECT (CATS_DIFF_TIME(start_date, submit_time + CA.diff_time) / 60)
#    FROM reqs R, contests C, contest_accounts CA 
#    WHERE R.contest_id=C.id AND CA.contest_id=C.id~);
#$c->execute;

#my $c = $dbh->prepare(
# qq~SELECT (((submit_time + CA.diff_time) - start_date) * 24 * 60)
#    FROM reqs R, contests C, contest_accounts CA 
#    WHERE R.contest_id=C.id AND CA.contest_id=C.id~);
#$c->execute;


#while (my ($t) = $c->fetchrow_array)
#{
#    print $t."\n";
#    last;
#}

my $t = 'Hide';
if ($t =~ /^hide$|^show$/)
{
    print "found";
}


$dbh->commit;

print "\ncompleted";
sql_disconnect;


