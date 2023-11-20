package CATS::Similarity;

use strict;
use warnings;

use Encode;
use Digest::MD5;

my $collapded_id = '_Q_';

sub preprocess_line {
    my ($s) = @_;
    use bytes; # MD5 works with bytes, prevent upgrade to utf8
    s/\s+//g;
    #s/#.+$//; s[//.+$][];
    if ($s->{collapse_idents}) {
        s/[a-zA-Z_][a-zA-Z_0-9]*/$collapded_id/g;
    }
    else {
        $_ = uc($_);
    }
    s/\d+/1/g if $s->{collapse_nums};
    $_;
}

sub preprocess_source {
    my ($req, $s, $debug) = @_;
    my $h = $req->{hash} = {};
    my $line = 0;
    my $max_lines = $s->{max_lines} || 1000;
    my @debug_src;
    for (split /\n/, $req->{src}) {
        ++$line < $max_lines or last;
        $_ = Encode::encode('WINDOWS-1251', $_);
        use bytes; # MD5 works with bytes, prevent upgrade to utf8
        s/\s+//g;
        #s/#.+$//; s[//.+$][];
        if ($s->{collapse_idents}) {
            s/[a-zA-Z_][a-zA-Z_0-9]*/$collapded_id/g;
        }
        else {
            $_ = uc($_);
        }
        s/\d+/1/g if $s->{collapse_nums};
        $debug ? push(@debug_src, $_) : ($h->{Digest::MD5::md5_hex($_)} = 1);
    }
    $debug && \@debug_src;
}

sub similarity_score {
    my ($i, $j) = @_;
    my $sim = 0;
    $sim++ for grep exists $j->{$_}, keys %$i;
    2 * $sim / (keys(%$i) + keys(%$j));
}

sub similarity_score_2 {
    my ($req1, $req2, $s) = @_;
    preprocess_source($_, $s) for ($req1, $req2);
    similarity_score(map $_->{hash}, $req1, $req2);
}

sub recommend_replacements {
    my ($req1, $req2, $s, $except) = @_;


    my $max_lines = $s->{max_lines} || 1000;
    my $line_num_1 = 0;
    my %renames;

    for my $line1 (split /\n/, $req1->{src}) {
        ++$line_num_1 < $max_lines or last;
        my @list1 = split /([a-zA-Z_][a-zA-Z_0-9]*)/, $line1;

        my $line_num_2 = 0;
        for my $line2 (split /\n/, $req2->{src}) {
            ++$line_num_2 < $max_lines or last;
            next if $line1 eq $line2;
            my @list2 = split /([a-zA-Z_][a-zA-Z_0-9]*)/, $line2;
            next if @list1 != @list2 || @list1 <= 1;

            my $is_similar = 1;
            my (%line_renames_count, %line_renames);
            for (my $i = 0; $i < @list1; $i += 2) {
                $list1[$i] =~ s/\s+//g;
                $list2[$i] =~ s/\s+//g;
                $is_similar = $list1[$i] eq $list2[$i] or last;

                $i + 1 < @list1 or last;
                my ($id1, $id2) = ($list1[$i + 1], $list2[$i + 1]);

                $line_renames{$id1} //= $id2;
                $is_similar = $line_renames{$id1} eq $id2 or last;

                next if $id1 eq $id2 || $except->{$id1} || $except->{$id2};

                ++$line_renames_count{"$id1 $id2"};
            }

            if ($is_similar) {
                $renames{$_} += $line_renames_count{$_} for keys %line_renames_count;
            }
        }
    }
    my @result =
        sort { $renames{$b} <=> $renames{$a} || $a cmp $b } grep $renames{$_} > 1, keys %renames;
    (\@result, [ map $renames{$_}, @result ]);
}
1;
