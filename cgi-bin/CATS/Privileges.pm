package CATS::Privileges;

use strict;
use warnings;

use CATS::DB;

my $srole_root = 0;
our $srole_user = 1;

# Bit flag values for accounts.srole. Root includes all other roles.
my %flags = (
    create_contests => 2,
    moderate_messages => 4,
    delete_problems => 8,
    edit_sites => 16,
);

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
    $p->{$_} = $r || ($srole & $flags{$_}) for keys %flags;
    $p;
}

sub pack_privs {
    my ($p) = @_;
    return $srole_root if $p->{is_root};
    my $srole = $srole_user;
    $p->{$_} and $srole |= $flags{$_} for keys %flags;
    $srole;
}

sub all_names { sort 'is_root', keys %flags }

1;
