package CATS::Data;

use strict;
use warnings;

use CATS::DB;
use CATS::Misc qw($cid $is_jury $is_root $uid);
use CATS::Utils qw(state_to_display);

use Exporter qw(import);

our @EXPORT = qw(
    get_registered_contestant
    is_jury_in_contest
);

our %EXPORT_TAGS = (all => [ @EXPORT ]);

# Params: fields, contest_id, account_id.
sub get_registered_contestant
{
    my %p = @_;
    $p{fields} ||= 1;
    $p{account_id} ||= $uid or return;
    $p{contest_id} or die;

    $dbh->selectrow_array(qq~
        SELECT $p{fields} FROM contest_accounts WHERE contest_id = ? AND account_id = ?~, undef,
        $p{contest_id}, $p{account_id});
}

sub is_jury_in_contest
{
    my %p = @_;
    return 1 if $is_root;
    # Optimization: if the request is about the current contest, return cached value.
    if (defined $cid && $p{contest_id} == $cid) {
        return $is_jury;
    }
    my ($j) = get_registered_contestant(fields => 'is_jury', @_);
    return $j;
}

1;
