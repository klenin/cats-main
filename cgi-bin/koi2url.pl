use Encode;

my $text = 'Муниц';
map printf('%%%x', ord($_)), split //, Encode::encode_utf8(Encode::decode('KOI8-R', $text));
print "\n";
