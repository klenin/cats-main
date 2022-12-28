use v5.10;
use strict;
use warnings;

use Encode;
use File::Spec;
use FindBin;
use Getopt::Long;

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::DB;
use CATS::Privileges;

GetOptions(
    help => \(my $help = 0),
    'find=s' => \(my $find = 0),
    'id=i' => \(my $user_id = 0),
    'login=s' => \(my $user_login = ''),
    'add=s@' => (my $add = []),
    'remove=s@' => (my $remove = []),
    'multi-ip=i' => \(my $multi_ip),
);

sub usage {
    print STDERR qq~CATS Priviledge management tool
Usage: $0
  --help
  --id=<user id> --login=<user login> [--add=<priv>...] [--remove=<priv>...] [--multi-ip=<count>]
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

my $need_commit = 0;

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
if ($srole != $u->{srole}) {
    $dbh->do(q~
        UPDATE accounts SET srole = ?
        WHERE id = ? AND login = ?~, undef,
        $srole, $user_id, $user_login) == 1 or die;
    $need_commit = 1;
}

if (defined $multi_ip) {
    $dbh->do(q~
        UPDATE accounts SET multi_ip = ?
        WHERE id = ? AND login = ?~, undef,
        $multi_ip, $user_id, $user_login) == 1 or die;
    $need_commit = 1;
}

$dbh->commit if $need_commit;

say "Id      :  $u->{id}";
say "Login   :  $u->{login}";
say "SID     :  $u->{sid}";
say "SRole   :  $u->{srole}", ($srole != $u->{srole} ? " => $srole" : '');
say "Multi-IP:  ", $u->{multi_ip} // '0',
    (defined $multi_ip &&  $multi_ip != ($u->{multi_ip} // 0) ? " => $multi_ip" : '') if $u->{multi_ip} || defined $multi_ip;
say 'Privileges:';

for (sort keys %$p) {
    say $marks{$_} || '', "\t$_" if $p->{$_} || $marks{$_};
}

$dbh->disconnect;
