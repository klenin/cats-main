use v5.10;
use strict;
use warnings;

use Encode;
use File::Spec;
use FindBin;
use Getopt::Long;

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::Constants;
use CATS::Messages;

GetOptions(
    help => \(my $help = 0),
    'id=i' => \(my $string_id = 0),
    'find=s' => \(my $substr = ''),
    'lang=s' => \(my $lang = ''),
);

sub usage {
    print STDERR @_, "\n" if @_;
    print STDERR qq~CATS String management tool
Usage: $0 [--help] [--id=<string id>|--find=<substr>] [--lang=<lang>]
~;
    exit;
}

usage if $help;

CATS::Messages::init;

if ($string_id) {
    say "$_: ", Encode::encode_utf8(CATS::Messages::res_str_lang_raw($_, $string_id))
        for $lang ? $lang : @cats::langs;
}
elsif ($substr) {
    my @answers;
    my $decoded = Encode::decode_utf8($substr);
    for my $cur_lang ($lang ? $lang : @cats::langs) {
        my $r = CATS::Messages::find_res_str($cur_lang, $decoded) or next;
        push @answers,
            sprintf "%s: %d: %s", $cur_lang, map Encode::encode_utf8($_), @$_ for @$r;
    }
    if (@answers) {
        say for @answers;
    }
    else {
        printf "String '%s' not found\n", $substr;
    }
}
else {
    usage;
}
