# MathRender v1.2 by Matviyenko Victor  
use lib '../..';
use CATS::TeX::HTMLGen;
use CATS::TeX::MMLGen;
use strict;
use warnings;

sub test_gen
{
    my $output = 'res/out';
    print @ARGV;
    my ($count, $last); 
    for my $input (@ARGV? @ARGV : ('manytests.txt'))
    {
        open (IN, '<', $input) or die "no input";
        my @tst = <IN>;
        chomp @tst;
        for (@tst) 
        {
            ++$count;
            next if /^\s*#/;
            $last = $output."$count.html";
            open (OUT, '>', $last); 
            print OUT gen_html($_, font => "medium", step => "\t"); 
            open (OUT, '>', $output."$count.xhtml"); 
            print OUT CATS::TeX::MMLGen::gen_mml($_, step => " "); 
            # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! 
            #system "explorer.exe ".$last;
            # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        }
    }
} 

test_gen();

