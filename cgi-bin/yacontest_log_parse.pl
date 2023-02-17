use strict;
use warnings;

use Text::CSV;
use Getopt::Long;
use XML::Parser::Expat;

GetOptions(
    help => \(my $help = 0),
    'users=s' => \(my $users_fn = 'users.csv'),
    'log=s' => \(my $log_fn),
);

my $yc_col_name = 'CT_Yandex_Contest';

sub usage {
    print STDERR qq~CATS Yandex Contest log parser
Usage: $0
  --help
  --log=<file>, Yandex log, XML'
  --users=<csv file>, columns must contain: $yc_col_name, login; default is '$users_fn'
~;
    exit;
}

usage if $help || !$log_fn;

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
    my $csv = Text::CSV->new({ binary => 1 });
    open my $fh, '<', $users_fn or die "Couldn't open users '$users_fn': $!";
    $csv->header($fh, {
        sep_set => [ ';', ',', '|', "\t" ],
        munge_column_names => 'none',
    });
    grep $_ eq $yc_col_name, $csv->column_names or die "Column $yc_col_name not found";
    while (my $row = $csv->getline_hr($fh)) {
        my $yc = $row->{$yc_col_name} or next;
        $logins{$yc} = $row->{login};
        $users{$yc} = '?';
    }
}

$parser->setHandlers(Start => \&_on_start);
{
    open my $fh, '<', $log_fn or die "Couldn't open log '$log_fn': $!";
    $parser->parse($fh);
}

print "login\tpoints\tsource\n";
for my $yc (sort keys %users) {
    my $r = $results{$users{$yc}} or next;
    print $logins{$yc}, "\t", $r->{points}, "\t", $r->{solved}, "\n";
}
