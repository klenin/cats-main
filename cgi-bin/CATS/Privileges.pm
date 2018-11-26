package CATS::Privileges;

use strict;
use warnings;

use CATS::DB;

my $srole_root = 0;
our $srole_user = 1;

# Bit flag values for accounts.srole. Root includes all other roles.
my @flag_names = qw(
    create_contests
    moderate_messages
    delete_problems
    edit_sites
    manage_judges
);

my %flags = map { $flag_names[$_] => 2 << $_ } 0..$#flag_names;

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
    $p->{$_} = $r || ($srole & $flags{$_}) for @flag_names;
    $p;
}

sub pack_privs {
    my ($p) = @_;
    return $srole_root if $p->{is_root};
    my $srole = $srole_user;
    $p->{$_} and $srole |= $flags{$_} for @flag_names;
    $srole;
}

sub all_names { sort 'is_root', @flag_names }
sub ui_names { \@flag_names }

sub is_good_name { $_[0] eq 'is_root' || exists $flags{$_[0]} }

sub where_cond {
    my ($name) = @_;
    my $packed = pack_privs({ $name => 1 });
    $packed eq $srole_root ?
        ('srole = ?', $srole_root) :
        ('BIN_AND(srole, ?) = ?', $packed, $packed);
}

1;
