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

use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1], 'cats-problem');
use lib File::Spec->catdir((File::Spec->splitpath(File::Spec->rel2abs($0)))[0, 1]);

use CATS::Constants;
use CATS::Config;
use CATS::DB;
use CATS::Mail;
use CATS::Utils;

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

sub log_url {
    $CATS::Config::absolute_url .
        url_function('run_log', rid => $_[0]->{id}, cid => $_[0]->{contest_id}, sid => 'z')
}

{
    my $u = $dbh->selectall_arrayref(qq~
        SELECT R.id, R.contest_id FROM reqs R
            WHERE R.state = $cats::st_unhandled_error AND R.submit_time > CURRENT_TIMESTAMP - 30
            ORDER BY R.submit_time DESC~, { Slice => {} });
    $r->{long}->{'Unhandled errors'} = join "\n", scalar(@$u), map '    ' . log_url($_), @$u;
    $r->{short}->{U} = scalar @$u if @$u;
}

{
    my ($jalive, $jtotal) = CATS::Judge::get_active_count;
    $r->{long}->{'Judges total'} = $jtotal;
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
    my ($p) = $dbh->selectall_arrayref(q~
        SELECT id, title
            FROM problems P WHERE CURRENT_TIMESTAMP - P.upload_date <= 1~, { Slice => {} });
    if (@$p) {
        $r->{long}->{'Problems changed'} = join ', ', map '"' . Encode::decode_utf8($_->{title}) . '"', @$p;
    }
}

{
    my ($length) = $dbh->selectrow_array(q~
        SELECT SUM(OCTET_LENGTH(LD.dump))
            FROM log_dumps LD INNER JOIN reqs R ON R.id = LD.req_id
            WHERE R.submit_time > CURRENT_TIMESTAMP - 1~);
    if ($length) {
        $r->{long}->{'Log dump size'} = $length;
    }
}

$dbh->disconnect;

my $text = sprintf "Subject: CATS Health Report (%s)\n\n%s\n", $r->construct_short, $r->construct_long;

if ($output eq 'mail') {
    CATS::Mail::send($CATS::Config::health_report_email, $text);
}
else {
    print Encode::encode_utf8($text);
}
