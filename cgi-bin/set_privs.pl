use v5.10;
use strict;
use warnings;

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
);

sub usage {
    print STDERR qq~CATS Priviledge management tool
Usage: $0
  --help
  --id=<user id> --login=<user login> [--add=<priv>...] [--remove=<priv>...]
  --find=<priv>
Privileges:\n~;
    say "  $_" for CATS::Privileges::all_names;
    exit;
}

usage if $help || !$user_id && !$user_login && !$find;

$find || $user_id && $user_login or die 'Must use BOTH id and login';

CATS::DB::sql_connect({});

if ($find) {
    CATS::Privileges::is_good_name($find) or die "Unknown priviledge: $_";
    my ($cond, @params) = CATS::Privileges::where_cond($find);
    #$find eq 'is_root' ?
    my $users = $dbh->selectall_arrayref(qq~
        SELECT A.id, A.login FROM accounts A
        WHERE $cond~, undef,
        @params);
    say "Found: " . scalar(@$users);
    printf "  %10d %s\n", @$_ for @$users;
    exit;
}

my $users = $dbh->selectall_arrayref(q~
    SELECT id, login, srole FROM accounts
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
if ($srole != $u->{srole}) {
    $dbh->do(q~
        UPDATE accounts SET srole = ?
        WHERE id = ? AND login = ?~, undef,
        $srole, $user_id, $user_login) == 1 or die;
    $dbh->commit;
}

say "Id:\t$u->{id}";
say "Login:\t$u->{login}";
say "SRole:\t$u->{srole}", ($srole != $u->{srole} ? " => $srole" : '');
say 'Privileges:';

for (sort keys %$p) {
    say $marks{$_} || '', "\t$_" if $p->{$_} || $marks{$_};
}

$dbh->disconnect;
