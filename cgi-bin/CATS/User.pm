package CATS::User;

use strict;
use warnings;

use lib '..';

use CATS::Misc qw(init_template msg url_f);
use CATS::DB;
use CATS::Connect;
use CATS::Constants;


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
    $login_num or die;

    return "team$login_num";
}


sub new_frame 
{
    my $t = init_template('main_users_new.htm');
    $t->param(login => generate_login);
    $t->param(countries => \@cats::countries, href_action => url_f('users'));    
}


sub param_names ()
{
    qw(login team_name capitan_name email country motto home_page icq_number)
}


sub validate_params
{
    my ($up, %p) = @_;

    $up->{login} && length $up->{login} <= 100
        or return msg(101);

    $up->{team_name} && length $up->{team_name} <= 100
        or return msg(43);

    length $up->{capitan_name} <= 100
        or return msg(45);

    length $up->{motto} <= 200
        or return msg(44);

    length $up->{home_page} <= 100
        or return msg(48);

    length $up->{icq_number} <= 100
        or return msg(47);

    if ($p{validate_password})
    {
        $up->{password1} ne '' && length $up->{password1} <= 100
            or return msg(102);

        $up->{password1} eq $up->{password2}
            or return msg(33);
        msg(85);
    }
    return 1;
}


1;
