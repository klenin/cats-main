use v5.10;
use strict;
use warnings;

use Encode;
use File::Spec;
use FindBin;
use Getopt::Long;
use SQL::Abstract; # Actually used by CATS::DB, but is optional there.

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::ConsoleColor qw(colored maybe_colored);
use CATS::DB;
use CATS::Privileges;

use constant COLOR_SUCCESS => 'green';
use constant COLOR_MARK => { '+' => 'green', '-' => 'red' };

GetOptions(
    help => \(my $help = 0),
    'find=s' => \(my $find = 0),
    'id=i' => \(my $user_id = 0),
    'login=s' => \(my $user_login = ''),
    'add=s@' => (my $add = []),
    'remove=s@' => (my $remove = []),
    'sid=s' => \(my $new_sid = ''),
    'multi-ip=i' => \(my $multi_ip),
);

sub usage {
    print STDERR qq~CATS Priviledge management tool

Usage: $0
  --help
  --id=<user id> --login=<user login>
    [--add=<priv>...] [--remove=<priv>...] [--multi-ip=<count>] [--sid=<sid>]
  --find=<priv>|any_jury

Privileges:\n~;
    say "  $_" for CATS::Privileges::all_names;
    exit;
}

usage if $help || !$user_id && !$user_login && !$find;

$find || $user_id && $user_login or die 'Must use BOTH id and login';

CATS::DB::sql_connect({});

sub make_find_cond {
    $find eq 'any_jury' and return (q~
        EXISTS (SELECT 1 FROM contest_accounts CA WHERE CA.account_id = A.id AND Ca.is_jury = 1)~, ());
    CATS::Privileges::is_good_name($find) or die "Unknown priviledge: $find";
    CATS::Privileges::where_cond($find);
}

if ($find) {
    my ($cond, @params) = make_find_cond;
    #$find eq 'is_root' ?
    my $users = $dbh->selectall_arrayref(qq~
        SELECT A.id, A.login FROM accounts A
        WHERE $cond~, undef,
        @params);
    say "Found: " . scalar(@$users);
    printf "  %10d %s\n", $_->[0], Encode::encode_utf8($_->[1]) for @$users;
    exit;
}

my $users = $dbh->selectall_arrayref(q~
    SELECT id, login, srole, multi_ip, sid FROM accounts
    WHERE id = ? AND login = ?~, { Slice => {} },
    $user_id, $user_login);

@$users == 1 or die "User not found";

my $u = $users->[0];
my $p = CATS::Privileges::unpack_privs($u->{srole});

for (@$add, @$remove) {
    exists $p->{$_} or die "Unknown priviledge: $_";
}

my %marks;

for (@$add) {
    if ($p->{$_}) {
        print STDERR "User already has priviledge $_\n";
        next;
    }
    $p->{$_} = 1;
    $marks{$_} = '+';
}

for (@$remove) {
    if (!$p->{$_}) {
        print STDERR "User already does not have priviledge $_\n";
        next;
    }
    $p->{$_} = 0;
    $marks{$_} = '-';
}

my $srole = CATS::Privileges::pack_privs($p);

my $update = {
    ($srole != $u->{srole} ? (srole => $srole) : ()),
    (defined $multi_ip && $multi_ip != ($u->{multi_ip} // 0) ? (multi_ip => $multi_ip) : ()),
    ($new_sid ne '' && $new_sid ne $u->{sid} ? (sid => $new_sid) : ()),
};

my $need_commit = 0;

if (%$update) {
    $dbh->do(_u $sql->update('accounts', $update, { id => $user_id, login => $user_login }))
        or die 'Update failed';
    say colored('Update successfull', COLOR_SUCCESS);
    $need_commit = 1;
}

$dbh->commit if $need_commit;

sub _display_new { exists $update->{$_[0]} ? colored(" => $update->{$_[0]}", COLOR_SUCCESS) : '' }

say "Id      :  $u->{id}";
say "Login   :  $u->{login}";
say "SID     :  $u->{sid}", _display_new('sid');
say "SRole   :  $u->{srole}", _display_new('srole');
say "Multi-IP:  ", $u->{multi_ip} // '0', _display_new('multi_ip')
    if $u->{multi_ip} || defined $multi_ip;
say 'Privileges:';

for (sort keys %$p) {
    $p->{$_} || $marks{$_} or next;
    my $m = $marks{$_} || '';
    say maybe_colored("$m\t$_", COLOR_MARK->{$m});
}

$dbh->disconnect;
