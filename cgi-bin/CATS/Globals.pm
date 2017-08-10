package CATS::Globals;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(
    $cid $contest $is_jury $is_team $is_root $privs $sid $t $uid $user
);

our (
    $cid, $contest, $is_jury, $is_root, $is_team, $privs, $t, $sid, $uid, $user
);

1;
