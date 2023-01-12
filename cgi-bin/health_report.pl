use strict;
use warnings;

use Carp;
use Encode;
use File::Spec;
use FindBin;
use Getopt::Long;

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::Config;
use CATS::DB;
use CATS::Mail;
use CATS::Report;

GetOptions(
    help => \(my $help = 0),
    'output=s' => \(my $output = ''),
    'report=s' => \(my $report_filter = ''),
    verbose => \(my $verbose = 0),
);

sub usage {
    my ($msg) = @_;
    print STDERR "$msg\n" if $msg;
    print STDERR qq~
CATS Reporting tool
Usage: $0 [--help] --output={std|mail} [--verbose] [--report=item{,item...}]
Available items (default: All):
~;
    for my $ri (@$CATS::Report::items) {
        print STDERR "$ri->{name}\t$ri->{long}\n";
    }
    exit;
}

usage if $help;

$SIG{__DIE__} = \&Carp::confess if $verbose;

if (!$output || $output !~ /^(std|mail)$/) {
    usage 'Wrong or missing --output parameter';
}

my %use_report_items = map { $_->{name} => 1 } @$CATS::Report::items;
if ($report_filter) {
    for (split /,/, $report_filter) {
        $use_report_items{$_} or usage "Unknown --report item: $_";
        $use_report_items{$_} = 2;
    }
}

CATS::DB::sql_connect({
    ib_timestampformat => '%d.%m.%Y %H:%M',
    ib_dateformat => '%d.%m.%Y',
    ib_timeformat => '%H:%M:%S',
});

my $r = CATS::Report->new;

for my $ri (@$CATS::Report::items) {
    next if $use_report_items{$ri->{name}} != ($report_filter ? 2 : 1);
    print "$ri->{long}...\n" if $verbose;
    my ($long, $short) = $ri->{get}->();
    $r->{long}->{$ri->{long}} = $long if defined $long;
    $r->{short}->{$ri->{short}} = $short if defined $short;
}

$dbh->disconnect;

my $text = sprintf "Subject: CATS Health Report (%s)\n\n%s\n", $r->construct_short, $r->construct_long;

if ($output eq 'mail') {
    CATS::Mail::send($CATS::Config::health_report_email, $text, verbose => $verbose);
}
else {
    print Encode::encode_utf8($text);
}
