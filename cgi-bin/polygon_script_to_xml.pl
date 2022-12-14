use strict;
use warnings;

# Copypasted from CATS::Testset to avoid dependency.
sub pack_rank_spec {
    my ($prev, @ranks) = sort { $a <=> $b } @_ or return '';
    @ranks or return "$prev";
    my @ranges;
    my ($state, $from, $to, $step) = (2);
    for (@ranks, 0, -1) {
        if ($state == 2) {
            $step = $_ - $prev;
            $state = 3;
        }
        elsif ($state == 3) {
            if ($prev + $step == $_) {
                ($state, $from, $to) = (4, $prev - $step, $_);
            }
            else {
                push @ranges, $prev - $step;
                $step = $_ - $prev;
            }
        }
        elsif ($state == 4) {
            if ($prev + $step == $_) {
                $to = $_;
            }
            else {
                push @ranges, "$from-$to" . ($step > 1 ? "-$step" : '');
                $state = 2;
            }
        }
        $prev = $_;
    }
    join ',', @ranges;
}

my $re = qr/^(\d+)\s+\-+\s+"([\w\-]+)(?:\s+([^"]+))?\"$/;
my @lines = <>;

my %gens;
/$re/ and $gens{$2} = 1 for @lines;
my @gens = keys %gens;

for my $gen (keys %gens) {
    print qq~<Generator name="$gen" src="$gen.cpp" de_code="102" />\n~;
}

print "\n";

my ($t_min, $t_max) = (1e100, -1);
my $subtasks = {};
my $cur_subtask;

for my $line (@lines) {
    chomp $line;
    if (!$line) {
        print "\n";
    }
    elsif ($line =~ /^(\d+)\s+\-+\s+manual$/) {
        print qq~<Test rank="$1"><In src="%0n"/></Test>\n~;
        $cur_subtask->{$1} = 1 if $cur_subtask;
    }
    elsif (my ($num, $gen, $params) = $line =~ /$re/) {
        $t_min = $num if $num < $t_min;
        $t_max = $num if $num > $t_max;
        my $use = @gens > 1 ? qq~ use="$gen"~ : '';
        my $param = $params ? qq~ param="$params"~ : '';
        print qq~<Test rank="$num"><In$use$param/></Test>\n~;
        $cur_subtask->{$1} = 1 if $cur_subtask;
    }
    else {
        print qq~<!-- $line -->\n~;
        if ($line =~ /^\s*Subtask\s+(\d+)\s*$/) {
            $subtasks->{$1} = $cur_subtask = {};
        }
    }
}

if (@gens == 1) {
    print qq~\n<Test rank="$t_min-$t_max"><In use="@gens"/></Test>\n~;
}

print "\n" if %$subtasks;
for my $st (sort { $a <=> $b } keys %$subtasks) {
    my $tests = pack_rank_spec(keys %{$subtasks->{$st}});
    print qq~<Testset name="subtask$st" tests="$tests" points="0" />\n~;
}
