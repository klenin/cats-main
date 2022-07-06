use strict;
use warnings;

use File::Spec;
use FindBin;

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::Globals qw($cid $sid);
use CATS::Examus;

$cid = 1234;
$sid = 'sdfdsfsdf';

my $e = CATS::Examus->new(
    secret => 's4EZ95RxM@UQpCY3$MrC!ptnn&mT%P&T',
    start_date => '29.01.2022 23:50',
    finish_date => '30.01.2022 02:50',
);

print($e->make_jws_token);
