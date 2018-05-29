use strict;
use warnings;

use Apache2::RequestRec ();
use Apache2::Request;
use Apache2::RequestIO ();
use Apache2::Const -compile => ':common';
use Apache2::Log;

use FindBin;

my $cats_lib_dir;
my $cats_problem_lib_dir;
BEGIN {
    $cats_lib_dir = $ENV{CATS_DIR} || $FindBin::Bin . '/..';
    $cats_lib_dir =~ s/\/$//;
    $cats_problem_lib_dir = "$cats_lib_dir/cats-problem";
}

use lib $cats_lib_dir;
use lib $cats_problem_lib_dir;

# use Carp;
# $SIG{__WARN__} = \&confess;

1;