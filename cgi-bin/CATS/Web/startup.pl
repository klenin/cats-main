use Apache2::RequestRec ();
use Apache2::Request;
use Apache2::Const -compile => ":common";

our $cats_lib_dir;
BEGIN {
    $cats_lib_dir = $ENV{CATS_DIR} || '.';
    $cats_lib_dir =~ s/\/$//;
}

use lib $cats_lib_dir;


1;