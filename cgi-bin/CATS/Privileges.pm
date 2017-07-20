package CATS::Privileges;

use strict;
use warnings;

use CATS::DB;

# Bit flag values for accounts.srole. Root includes all other roles.
my $srole_root = 0;
our $srole_user = 1;
my $srole_contests_creator = 2;
my $srole_messages_moderator = 4;
my $srole_problems_deleter = 8;

sub get_root_account_ids {
    $dbh->selectcol_arrayref(q~
        SELECT id FROM accounts WHERE srole = ?~, undef,
        $srole_root);
}

sub is_root { $_[0] == $srole_root }

sub unpack_privs {
    my ($srole) = @_;
    my $p = {};
    my $r = $p->{is_root} = is_root($srole);
    $p->{create_contests} = $r || ($srole & $srole_contests_creator);
    $p->{moderate_messages} = $r || ($srole & $srole_messages_moderator);
    $p->{delete_problems} = $r || ($srole & $srole_problems_deleter);
    $p;
}

1;
