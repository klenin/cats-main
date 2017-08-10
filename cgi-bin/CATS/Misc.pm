package CATS::Misc;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(
    $cid $contest $is_jury $is_team $is_root $privs $sid $t $uid $user
    auto_ext
    downloads_path
    downloads_url
    generate_output
    init_template
    url_f
);

use Encode();
use SQL::Abstract; # Actually used by CATS::DB, bit is optional there.

use CATS::Config qw(cats_dir);
use CATS::Constants;
use CATS::DB;
use CATS::Template;
use CATS::Utils qw();
use CATS::Web qw(param url_param headers content_type);

our (
    $contest, $t, $sid, $cid, $uid,
    $is_root, $is_team, $is_jury, $privs, $user,
);

my ($http_mime_type, %extra_headers);

sub http_header {
    my ($type, $encoding, $cookie) = @_;

    content_type($type, $encoding);
    headers(cookie => $cookie, %extra_headers);
}

sub downloads_path { cats_dir() . '../download/' }
sub downloads_url { 'download/' }

sub auto_ext {
    my ($file_name, $json) = @_;
    my $ext = $json // param('json') ? 'json' : 'html';
    "$file_name.$ext.tt";
}

#my $template_file;
sub init_template {
    my ($file_name, $p) = @_;
    #if (defined $t && $template_file eq $file_name) { $t->param(tf=>1); return; }

    my ($base_name, $ext) = $file_name =~ /^(\w+)\.(\w+)(:?\.tt)$/;
    $http_mime_type = {
        htm => 'text/html',
        html => 'text/html',
        xml => 'application/xml',
        ics => 'text/calendar',
        json => 'application/json',
    }->{$ext} or die 'Unknown template extension';
    %extra_headers = $ext eq 'ics' ?
        ('Content-Disposition' => "inline;filename=$base_name.ics") : ();
    #$template_file = $file_name;
    $t = CATS::Template->new($file_name, cats_dir(), $p);
    my $json = param('json') || '';
    $extra_headers{'Access-Control-Allow-Origin'} = '*' if $json;
    $t->param($json =~ /^[a-zA-Z][a-zA-Z0-9_]+$/ ? (jsonp => $json) : ());
}

sub url_f { CATS::Utils::url_function(@_, sid => $sid, cid => $cid) }

sub generate_output {
    my ($output_file, $cookie) = @_;
    defined $t or return; #? undef : ref $t eq 'SCALAR' ? return : die 'Template not defined';
    $contest->{time_since_start} or warn 'No contest from: ', $ENV{HTTP_REFERER} || '';
    $t->param(
        contest_title => $contest->{title},
        user => $user,
        dbi_profile => $dbh->{Profile}->{Data}->[0],
        #dbi_profile => Data::Dumper::Dumper($dbh->{Profile}->{Data}),
        langs => [ map { href => url_f('contests', lang => $_), name => $_ }, @cats::langs ],
    );

    my $out = '';
    if (my $enc = param('enc')) {
        $t->param(encoding => $enc);
        http_header($http_mime_type, $enc, $cookie);
        CATS::Web::print($out = Encode::encode($enc, $t->output, Encode::FB_XMLCREF));
    }
    else {
        $t->param(encoding => 'UTF-8');
        http_header($http_mime_type, 'utf-8', $cookie);
        CATS::Web::print($out = $t->output);
    }
    if ($output_file) {
        open my $f, '>:utf8', $output_file
            or die "Error opening $output_file: $!";
        print $f $out;
    }
}

1;
