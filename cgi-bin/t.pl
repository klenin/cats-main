
use strict;

use lib '.';

use CGI qw(:standard);
my $q = new CGI;
print url_param('a'), "\n";
restore_parameters({a=>2});
$ENV{QUERY_STRING} = 'a=5';
print url_param('a'), "\n";

#my $t = '/cats/static/problem_text/pid_923847_cid_938474.html';
#my ($f, $p) = $t =~ /^\/\w+\/static\/([a-z_]+)\/([a-z_0-9]+)\.html/;
#my %params;
#$p =~ s/([a-z]+)_(\d+)/$params{$1} = $2/eg;
#print $f, "\n", %params, "\n";


