package CATS::Report;

sub new {
    bless {
        short => {},
        long => {},
    }, shift;
}

sub construct_short {
    my ($self) = @_;
    my $s = $self->{short};
    %$s ? join ' ', map "$_=$s->{$_}", sort keys %$s : 'ok';
}

sub construct_long {
    my ($self) = @_;
    join "\n", map "$_: $self->{long}->{$_}", sort keys %{$self->{long}};
}

package main;

use strict;
use warnings;

use File::Spec;
use Getopt::Long;
use Net::SMTP::SSL;

use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1], 'cats-problem');

use CATS::Constants;
use CATS::Config;
use CATS::DB;

GetOptions(help => \(my $help = 0), 'output=s' => \(my $output = ''));

sub usage {
    print STDERR "CATS Reporting tool\nUsage: $0 [--help] --output={std|mail}\n";
    exit;
}

usage if $help;

if (!$output || $output !~ /^(std|mail)$/) {
    print STDERR "Wrong or missing --output parameter\n";
    usage;
}

my $r = CATS::Report->new;

CATS::DB::sql_connect({
    ib_timestampformat => '%d.%m.%Y %H:%M',
    ib_dateformat => '%d.%m.%Y',
    ib_timeformat => '%H:%M:%S',
});

{
    $r->{long}->{'Queue length'} = my $ql = $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM reqs R
            WHERE R.state = $cats::st_not_processed AND R.submit_time > CURRENT_TIMESTAMP - 30~);
    $r->{short}->{Q} = $ql if $ql > 1;
}

{
    my ($u) = $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM reqs R
            WHERE R.state = $cats::st_unhandled_error AND R.submit_time > CURRENT_TIMESTAMP - 30~);
    $r->{long}->{'Unhandled errors'} = $u;
    $r->{short}->{U} = $u if $u;
}

{
    my ($jtotal, $jalive) = $dbh->selectrow_array(qq~
        SELECT SUM(CASE WHEN CURRENT_TIMESTAMP - J.alive_date < ? THEN 1 ELSE 0 END), COUNT(*)
            FROM judges J WHERE J.lock_counter = 0~, undef,
        3 * $CATS::Config::judge_alive_interval);
    $r->{long}->{'Judges active'} = $jtotal;
    $r->{long}->{'Judges alive'} = $jalive;
    $r->{short}->{J} = "$jalive/$jtotal" if $jalive < $jtotal || !$jtotal;
}

$dbh->disconnect;

my $text = sprintf "Subject: CATS Health Report (%s)\n\n%s\n", $r->construct_short, $r->construct_long;

if ($output eq 'mail') {
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
    $mailer->datasend($text) or die $mailer->message;
    $mailer->dataend or die $mailer->message;
    $mailer->quit or die $mailer->message;
}
else {
    print $text;
}
