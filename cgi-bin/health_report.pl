use strict;
use warnings;

use File::Spec;
use Net::SMTP::SSL;
use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1], 'cats-problem');

use CATS::Constants;
use CATS::Config;
use CATS::DB;

CATS::DB::sql_connect({
    ib_timestampformat => '%d.%m.%Y %H:%M',
    ib_dateformat => '%d.%m.%Y',
    ib_timeformat => '%H:%M:%S',
});
my $queue_length = $dbh->selectrow_array(qq~
    SELECT COUNT(*) FROM reqs R
        WHERE R.state = $cats::st_not_processed AND R.submit_time > CURRENT_TIMESTAMP - 30~);
$dbh->disconnect;

my $short = $queue_length <= 1 ? '(ok)' : "(Q=$queue_length)";
my $long = "Queue length: $queue_length";

my $s = $CATS::Config::smtp;
my $mailer = Net::SMTP::SSL->new(
    $s->{server},
    Hello => $s->{server},
    Port => $s->{port},
);

$mailer->auth($s->{login}, $s->{password}) or die $mailer->message;
$mailer->mail($s->{email}) or die $mailer->message;
$mailer->to($CATS::Config::health_report_email) or die $mailer->message;
$mailer->data or die $mailer->message;
$mailer->datasend("Subject: CATS Health Report $short\n\n$long") or die $mailer->message;
$mailer->dataend or die $mailer->message;
$mailer->quit or die $mailer->message;
