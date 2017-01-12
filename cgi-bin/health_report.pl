use strict;
use warnings;

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

use Encode;
use File::Spec;
use Getopt::Long;
use Net::SMTP::SSL;

use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1], 'cats-problem');
use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1]);

use CATS::Constants;
use CATS::Config;
use CATS::DB;

use CATS::Judge;

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
    $r->{long}->{'Requests today'} = $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM reqs R
            WHERE R.submit_time > CURRENT_TIMESTAMP - 1~);
}

{
    my $u = $dbh->selectcol_arrayref(qq~
        SELECT R.id FROM reqs R
            WHERE R.state = $cats::st_unhandled_error AND R.submit_time > CURRENT_TIMESTAMP - 30~);
    $r->{long}->{'Unhandled errors'} = join ' ', scalar(@$u), @$u;
    $r->{short}->{U} = scalar @$u if @$u;
}

{
    my ($jtotal, $jalive) = CATS::Judge::get_active_count;
    $r->{long}->{'Judges active'} = $jtotal;
    $r->{long}->{'Judges alive'} = $jalive;
    $r->{short}->{J} = "$jalive/$jtotal" if $jalive < $jtotal || !$jtotal;
}

{
    $r->{long}->{'Questions unanswered'} = my $q = $dbh->selectrow_array(q~
        SELECT COUNT(*) FROM questions Q
            WHERE Q.clarified = 0 AND Q.submit_time > CURRENT_TIMESTAMP - 30~);
    $r->{short}->{'?'} = $q if $q;
}

{
    my ($p) = $dbh->selectall_arrayref(qq~
        SELECT id, title
            FROM problems P WHERE CURRENT_TIMESTAMP - P.upload_date <= 1~, { Slice => {} });
    if (@$p) {
        $r->{long}->{'Problems changed'} = join ', ', map '"' . Encode::decode_utf8($_->{title}) . '"', @$p;
    }
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
    print Encode::encode_utf8($text);
}
