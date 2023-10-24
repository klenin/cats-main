package CATS::Output;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(
    downloads_path
    downloads_url
    init_template
    search
    url_f
    url_f_cid
);

use Encode();

use CATS::Config qw(cats_dir);
use CATS::Globals qw($cid $contest $sid $t $user);
use CATS::DB;
use CATS::Messages qw(msg);
use CATS::Settings;
use CATS::Template;
use CATS::Utils qw();

my ($http_mime_type, %extra_headers);

sub downloads_path { cats_dir() . '../download/' }
sub downloads_url { 'download/' }
sub downloads_url_files { downloads_url . 'f/' }

my @nonce_ch = ('A'..'Z', 'a'..'z', '0'..'9');
sub make_nonce {
    join '', map { $nonce_ch[rand @nonce_ch] } 1..32;
}

# When Config::DOWN = 1, $user might be auto-vivified to an empty hash.
sub is_root_safe { $user && ref $user eq 'CATS::CurrentUser' && $user->is_root }

sub init_template {
    my ($p, $file_name, $extra) = @_;

    my ($base_name, $ext) = $file_name =~ /^(\w+)(?:\.(\w+)(:?\.tt))?$/ or die;
    $ext //=
        $p->{json} ? 'json' :
        $p->{ical} ? 'ics' :
        is_root_safe && @{$p->{csv}} ? 'csv':
        'html';

    $http_mime_type = {
        html => 'text/html',
        xml => 'application/xml',
        ics => 'text/calendar',
        json => 'application/json',
        csv => 'text/csv',
    }->{$ext} or die 'Unknown template extension';
    $t = CATS::Template->new("$base_name.$ext.tt", cats_dir(), $extra);

    %extra_headers = (
        ($ext =~ /^(ics|csv)$/ ?
            ('Content-Disposition' => "inline;filename=$base_name.$ext") : ()),
        ($p->{json} ?
            ('Access-Control-Allow-Origin' => '*') : ()),
    );
    $t->param(
        lang => CATS::Settings::lang,
        ($p->{jsonp} ? (jsonp => $p->{jsonp}) : ()),
        messages => CATS::Messages::get,
        user => $user,
        contest => $contest,
        href_contest_title => url_f($user->{is_jury} ? 'contest_params' : 'problems'),
        noiface => $p->{noiface},
        settings => $CATS::Settings::settings,
        nonce => make_nonce,
        web => $p,
    );

    $t;
}

sub url_f { CATS::Utils::url_function(@_, sid => $sid, cid => $cid) }
sub url_f_cid { CATS::Utils::url_function(@_, sid => $sid) }

sub search {
    (search => join ',', map "$_[$_ * 2]=$_[$_ * 2 + 1]", 0 .. int(@_ / 2) - 1)
}

sub _csv_quote {
    my ($v) = @_;
    defined $v or return '';
    $v = join ' ', @$v if ref $v eq 'ARRAY';
    $v =~ /["\s,;]/ or return $v;
    $v =~ s/"/""/g;
    qq~"$v"~;
}

sub _generate_csv {
    my ($p, $vars) = @_;
    my @fields = @{$p->{csv}};
    my $sep = $p->{csv_sep} || "\t";
    my @res = join $sep, @fields;
    my $an = $vars->{lv_array_name} or return '';
    for my $row (@{$vars->{$an}}) {
        push @res, join $sep, map _csv_quote($_),
            ref $row eq 'HASH' ? @$row{@fields} : @$row;
    }
    join "\n", @res;
}

sub generate {
    my ($p, $output_file) = @_;
    defined $t or return; #? undef : ref $t eq 'SCALAR' ? return : die 'Template not defined';
    $p->{down} || $contest->{time_since_start} or warn 'No contest from: ', $ENV{HTTP_REFERER} || '';
    $t->param(
        dbi_profile => $dbh && $dbh->{Profile}->{Data}->[0],
        #dbi_profile => Data::Dumper::Dumper($dbh->{Profile}->{Data}),
    ) unless $p->{notime};
    $t->param(
        langs => [ map { href => url_f('contests', lang => $_), name => $_ }, @cats::langs ],
    );

    my $cookie = $p->make_cookie(CATS::Settings::as_cookie);
    my $enc = $p->{enc} // 'UTF-8';
    $t->param(encoding => $enc);

    $p->content_type($http_mime_type, $enc);
    $p->headers(cookie => $cookie, %extra_headers);

    my $decoded_out =
        is_root_safe && $http_mime_type eq 'text/csv' ?
        _generate_csv($p, $t->{vars}) : $t->output;
    my $out = $enc eq 'UTF-8' ? $decoded_out : Encode::encode($enc, $decoded_out, Encode::FB_XMLCREF);
    $p->print($out);
    if ($output_file) {
        open my $f, '>:utf8', $output_file
            or die "Error opening $output_file: $!";
        print $f $out;
    }
}

sub down {
    my ($p) = @_;
    CATS::Settings::init(undef, $p->web_param('lang'), $p->get_cookie('settings'));
    init_template($p, 'down');
    $p->{down} = 1;
    generate($p);
    $p->get_return_code;
}

1;
