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
    'string=i' => \(my $string_id = 0),
    'lang=s' => \(my $lang = ''),
);

sub usage {
    print STDERR @_, "\n" if @_;
    print STDERR qq~CATS String management tool
Usage: $0 [--help] --string=<string id> [--lang=<lang>]
~;
    exit;
}

usage if $help || !$string_id;

CATS::Messages::init;

say "$_: ", Encode::encode_utf8(CATS::Messages::res_str_lang($_, $string_id))
    for $lang ? $lang : @cats::langs;
