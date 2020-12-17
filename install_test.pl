use strict;
use warnings;

use File::Spec;
use FindBin qw($Bin);
use Getopt::Long;

use lib File::Spec->catdir($Bin, 'cgi-bin');

use CATS::Deploy;

GetOptions(pg => \(my $pg = 0));

if ($pg) {
    CATS::Deploy::create_db('postgres', 'test', 'test_user', 'test_password',
        pg_auth_type => 'trust', init_config => 1, host => 'localhost', quiet => 1);
} else {
    my $tmp_dir = File::Spec->catdir(File::Spec->tmpdir, 'cats');
    CATS::Deploy::create_db('interbase', 'test', 'sysdba', $ENV{ISC_PASSWORD}, dir => $tmp_dir,
        init_config => 1, host => 'localhost', driver => 'FirebirdEmbedded', quiet => 1);
}
