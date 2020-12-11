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


my $c = $dbh->prepare(qq~SELECT id FROM accounts WHERE srole=0~);
$c->execute;

while (my ($aid) = $c->fetchrow_array)
{
    my $d = $dbh->prepare(qq~SELECT id FROM contests~);
    $d->execute;
    while (my ($cid) = $d->fetchrow_array)
    {
#        print $aid." ".$cid;
        if ($dbh->selectrow_array(qq~SELECT id FROM contest_accounts WHERE contest_id=? AND account_id=?~, {}, $cid, $aid))
        {
            $dbh->do(qq~UPDATE contest_accounts SET is_admin=1, is_hidden=1, is_ooc=1, is_remote=1, is_jury=1, is_pop=0 WHERE contest_id=? AND account_id=?~,
                    {}, $cid, $aid);
        }
        else
        {
            $dbh->do(qq~INSERT INTO contest_accounts(id, contest_id, account_id, is_admin, is_jury, is_pop, is_hidden, is_ooc, is_remote)
                        VALUES (?,?,?,?,?,?,?,?,?)~, {}, new_id, $cid, $aid, 1, 1, 0, 1, 1, 1);

        }
    }
}

$dbh->commit;
sql_disconnect;
