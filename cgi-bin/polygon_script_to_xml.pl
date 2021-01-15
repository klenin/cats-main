use strict;
use warnings;

my $re = qr/^(\d+)\s+\-+\s+"(\w+)(?:\s+([^"]+))?\"$/;
my @lines = <>;

my %gens;
/$re/ and $gens{$2} = 1 for @lines;
my @gens = keys %gens;

for my $gen (keys %gens) {
    print qq~<Generator name="$gen" src="$gen.cpp" de_code="102" />\n~;
}

print "\n";

my ($t_min, $t_max) = (1e100, -1);

for my $line (@lines) {
    chomp $line;
    if (!$line) {
        print "\n";
    }
    elsif ($line =~ /^(\d+)\s+\-+\s+manual$/) {
        print qq~<Test rank="$1"><In src="%0n"/></Test>\n~;
    }
    elsif (my ($num, $gen, $params) = $line =~ /$re/) {
        $t_min = $num if $num < $t_min;
        $t_max = $num if $num > $t_max;
        my $use = @gens > 1 ? qq~ use="$gen"~ : '';
        my $param = $params ? qq~ param="$params"~ : '';
        print qq~<Test rank="$num"><In$use$param/></Test>\n~;
    }
    else {
        print qq~<!-- $line -->\n~;
    }
}

if (@gens == 1) {
    print qq~\n<Test rank="$t_min-$t_max"><In use="@gens"/></Test>\n~;
}
