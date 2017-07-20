use strict;
use warnings;

use File::Spec;
use Getopt::Long;

use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1], 'cats-problem');
use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1]);

use CATS::DB;
use CATS::Privileges;

GetOptions(
    help => \(my $help = 0),
    'id=i' => \(my $user_id = 0),
    'login=s' => \(my $user_login = ''),
);

sub usage {
    print STDERR "CATS Priviledge management tool\nUsage: $0 [--help] [--id=<user id> --login=<user login>]\n";
    exit;
}

usage if $help || !$user_id && !$user_login;

$user_id && $user_login or die 'Must use BOTH id and login';

CATS::DB::sql_connect({});

my $users = $dbh->selectall_arrayref(q~
    SELECT id, login, srole FROM accounts WHERE id = ? AND login = ?~, { Slice => {} },
    $user_id, $user_login);

@$users == 1 or die "User not found";
my $u = $users->[0];

print "Id:\t$u->{id}\n";
print "Login:\t$u->{login}\n";
print "SRole:\t$u->{srole}\n";
print "Privileges:\n";

my $p = CATS::Privileges::unpack_privs($u->{srole});
for (sort keys %$p) {
    print "\t$_\n" if $p->{$_};
}

$dbh->disconnect;
