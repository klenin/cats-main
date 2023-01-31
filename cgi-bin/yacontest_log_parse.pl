use strict;
use warnings;

use Getopt::Long;
use XML::Parser::Expat;

GetOptions(
    help => \(my $help = 0),
    'users=s' => \(my $users_fn = 'users.csv'),
    'log=s' => \(my $log_fn = 'external.xml'),
);

sub usage {
    print STDERR qq~CATS Yandex Contest log parser
Usage: $0
  --help
  --log=<file>, Yandex log, XML; deafult is '$log_fn'
  --users=<file>, tab-seprated, columns should be: Yandex login, CATS login; default is '$users_fn'
~;
    exit;
}

usage if $help;

my $parser = XML::Parser::Expat->new;

my (%users, %logins, %results);

sub _on_start {
    my ($p, $el, %atts) = @_;
    if ($el eq 'user' && exists $users{$atts{loginName}}) {
        $users{$atts{loginName}} = $atts{id};
        $results{$atts{id}} = { points => 0, solved => '' };
    }
    elsif ($el eq 'submit' && (my $r = $results{$atts{userId}}) && $atts{verdict} eq 'OK') {
        $r->{points}++;
        $r->{solved} .= " $atts{problemTitle}";
    }
}

{
    open my $fh, '<', $users_fn or die "Couldn't open users '$users_fn': $!";
    while (<$fh>) {
        chomp;
        my ($yc, $login) = split /\t/;
        $logins{$yc} = $login;
        $users{$yc} = '?';
    }
}

$parser->setHandlers(Start => \&_on_start);
{
    open my $fh, '<', $log_fn or die "Couldn't open log '$log_fn': $!";
    $parser->parse($fh);
}

for my $yc (sort keys %users) {
    my $r = $results{$users{$yc}} or next;
    print $logins{$yc}, "\t", $r->{points}, "\t", $r->{solved}, "\n";
}
