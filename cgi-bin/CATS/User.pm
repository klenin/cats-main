package CATS::User;

use strict;
use warnings;


use lib '..';
use CATS::Web qw(param);
use CATS::Misc qw(init_template msg url_f);
use CATS::DB;
use CATS::Connect;
use CATS::Constants;
use CATS::Data;


sub new
{
    my ($class) = @_;
    $class = ref $class if ref $class;
    my $self = {};
    bless $self, $class;
    $self;
}


sub parse_params
{
   $_[0]->{$_} = param($_) || '' for param_names(), qw(password1 password2);
   $_[0];
}


sub load
{
    my ($self, $id) = @_;
    @$self{param_names()} = $dbh->selectrow_array(qq~
        SELECT ~ . join(', ' => param_names()) . q~
            FROM accounts WHERE id = ?~, { Slice => {} },
        $id
    ) or return;
    $self->{country} ||= $cats::countries[0]->{id};
    $_->{selected} = $_->{id} eq $self->{country} for @$cats::countries;
    $self;
}


sub values { @{$_[0]}{param_names()} }


sub add_to_contest
{
    my %p = @_;
    $p{contest_id} && $p{account_id} or die;
    $dbh->do(qq~
        INSERT INTO contest_accounts (
            id, contest_id, account_id, is_jury, is_pop, is_hidden, is_ooc, is_remote,
            is_virtual, diff_time
        ) VALUES(?,?,?,?,?,?,?,?,?,?)~, {},
        new_id, $p{contest_id}, $p{account_id}, 0, 0, 0, $p{is_ooc}, $p{is_remote} || 0,
        0, 0
    );
}


sub generate_login
{
    my $login_num;

    if ($CATS::Connect::db_dsn =~ /Firebird/) {
        $login_num = $dbh->selectrow_array('SELECT GEN_ID(login_seq, 1) FROM RDB$DATABASE');
    }
    elsif ($cats_db::db_dsn =~ /Oracle/) {
        $login_num = $dbh->selectrow_array(qq~SELECT login_seq.nextval FROM DUAL~);
    }
    $login_num or die;

    return "team$login_num";
}


sub new_frame
{
    my $t = init_template('users_new.html.tt');
    $t->param(login => generate_login);
    $t->param(countries => \@cats::countries, href_action => url_f('users'));
}


sub param_names ()
{
    qw(login team_name capitan_name email country motto home_page icq_number city)
}


sub any_official_contest_by_team
{
    my ($account_id) = @_;
    $dbh->selectrow_array(qq~
        SELECT FIRST 1 C.title FROM contests C
            INNER JOIN contest_accounts CA ON CA.contest_id = C.id
            INNER JOIN accounts A ON A.id = CA.account_id
            WHERE C.is_official = 1 AND CA.is_ooc = 0 AND CA.is_jury = 0 AND
            C.finish_date < CURRENT_TIMESTAMP AND A.id = ?~, undef,
        $account_id);
}


sub validate_params
{
    my ($self, %p) = @_;

    $self->{login} && length $self->{login} <= 50
        or return msg(101);

    $self->{team_name} && length $self->{team_name} <= 100
        or return msg(43);

    length $self->{capitan_name} <= 100
        or return msg(45);

    length $self->{motto} <= 200
        or return msg(44);

    length $self->{home_page} <= 100
        or return msg(48);

    length $self->{icq_number} <= 100
        or return msg(47);

    if ($p{validate_password}) {
        $self->{password1} ne '' && length $self->{password1} <= 100
            or return msg(102);

        $self->{password1} eq $self->{password2}
            or return msg(33);
        msg(85);
    }

    my $old_login = '';
    if ($p{id} && !$p{allow_official_rename}) {
        ($old_login, my $old_team_name) = $dbh->selectrow_array(qq~
            SELECT login, team_name FROM accounts WHERE id = ?~, undef,
            $p{id});
        if (($old_team_name ne $self->{team_name}) &&
            (my ($official_contest) = any_official_contest_by_team($p{id})))
        {
            # If the team participated in the official contest, forbid it to rename itself.
            return msg(86, $official_contest);
        }
    }

    return $old_login eq $self->{login} || $self->validate_login($p{id});
}


sub validate_login
{
    my ($self, $id) = @_;
    my $dups = $dbh->selectcol_arrayref(qq~
        SELECT id FROM accounts WHERE login = ?~, {}, $self->{login}) or return 1;
    # Several logins, or a single login with different id => error.
    return
        @$dups > 1 || @$dups == 1 && (!$id || $id != $dups->[0]) ? msg(103) : 1;
}


sub insert
{
    my ($self, $contest_id, %p) = @_;
    my $training_contests = $dbh->selectall_arrayref(qq~
        SELECT id, closed FROM contests WHERE ctype = 1 AND closed = 0~,
        { Slice => {} });
    @$training_contests or return msg(105);

    my $aid = new_id;
    my $new_settings = $p{save_settings} ? Storable::freeze($CATS::Misc::settings) : '';
    $dbh->do(qq~
        INSERT INTO accounts (
            id, srole, passwd, settings, ~ . join (', ', param_names()) . qq~
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)~, {},
        $aid, $cats::srole_user, $self->{password1}, $new_settings, $self->values
    );
    add_to_contest(contest_id => $_->{id}, account_id => $aid, is_ooc => 1)
        for @$training_contests;
    if ($contest_id && !grep $_->{id} == $contest_id, @$training_contests) {
        add_to_contest(contest_id => $contest_id, account_id => $aid, is_ooc => $p{is_ooc} // 1);
    }

    $dbh->commit if $p{commit} // 1;
    1;
}


# (Mass-)register users by jury.
sub register_by_login
{
    my ($login, $contest_id) = @_;
    my @logins = split(/\s*,\s*/, $login || '') or return msg(118);
    my %aids;
    for (@logins) {
        length $_ <= 50 or return msg(101);
        my ($aid) = $dbh->selectrow_array(qq~
            SELECT id FROM accounts WHERE login = ?~, undef, $_);
        $aid or return msg(118, $_);
        !get_registered_contestant(contest_id => $contest_id, account_id => $aid)
            or return msg(120, $_);
        $aids{$aid} = 1;
    }
    %aids or return msg(118);
    add_to_contest(contest_id => $contest_id, account_id => $_, is_remote => 1, is_ooc => 1)
        for keys %aids;
    $dbh->commit;
    msg(119, $login);
}


1;
