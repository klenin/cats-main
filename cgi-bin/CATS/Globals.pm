package CATS::Globals;

use strict;
use warnings;

use Exporter qw(import);

# $cid = $contest->{id}
# $is_jury = $user->{is_jury}
# $is_root = $user->privs->{is_root}
# $uid = $user->id
our @EXPORT_OK = qw(
    $cid $contest $is_jury $is_root $sid $t $uid $user
);

our (
    $cid, $contest, $is_jury, $is_root, $t, $sid, $uid, $user
);

# Optimization: limit datasets by both maximum row count and maximum visible pages.
sub max_fetch_row_count() { 1000 }

1;
