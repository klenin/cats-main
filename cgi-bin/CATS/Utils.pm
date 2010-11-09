package CATS::Utils;

BEGIN {
    use Exporter;

    @ISA = qw(Exporter);
    @EXPORT = qw(
        coalesce
        split_fname
        escape_html
        escape_xml
        url_function
        state_to_display
        source_hash
        param_on
    );

    %EXPORT_TAGS = (all => [@EXPORT]);
}

use strict;
use warnings;

use Text::Balanced qw(extract_tagged extract_bracketed);
use Digest::MD5;


sub coalesce { defined && return $_ for @_ }


sub split_fname
{
    my $path = shift;

    my ($vol, $dir, $fname, $name, $ext);

    my $volRE = '(?:^(?:[a-zA-Z]:|(?:\\\\\\\\|//)[^\\\\/]+[\\\\/][^\\\\/]+)?)';
    my $dirRE = '(?:(?:.*[\\\\/](?:\.\.?$)?)?)';
    if ($path =~ m/($volRE)($dirRE)(.*)$/)
    {
        $vol = $1;
        $dir = $2;
        $fname = $3;
    }

    if ($fname =~ m/^(.*)(\.)(.*)/)
    {
        $name = $1;
        $ext = $3;
    }

    return ($vol, $dir, $fname, $name, $ext);
}


sub escape_html
{
    my $toencode = shift;

    $toencode =~ s/&/&amp;/g;
    $toencode =~ s/\'/&#39;/g;
    $toencode =~ s/\"/&quot;/g; #"
    $toencode =~ s/>/&gt;/g;
    $toencode =~ s/</&lt;/g;

    return $toencode;
}


sub escape_xml
{
    my $t = shift;

    $t =~ s/&/&amp;/g;
    $t =~ s/>/&gt;/g;
    $t =~ s/</&lt;/g;

    return $t;
}

sub escape_url
{
    my ($url) = @_;
    $url =~ s/([\?=%;&])/sprintf '%%%02X', ord($1)/eg;
    $url;
}

sub gen_url_params
{
    my (%p) = @_;
    map { defined $p{$_} ? "$_=" . escape_url($p{$_}) : () } keys %p;
}


sub url_function
{
  my ($f, %p) = @_;
  join ';', "main.pl?f=$f", gen_url_params(%p);
}


# unused
sub generate_password
{
    my @ch1 = ('e', 'y', 'u', 'i', 'o', 'a');
    my @ch2 = ('w', 'r', 't', 'p', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'z', 'x', 'c', 'v', 'b', 'n', 'm');

    my $passwd = '';

    for (1..3)
    {
        $passwd .= @ch1[rand(@ch1)];
        $passwd .= @ch2[rand(@ch2)];
    }

    return $passwd;
}


sub state_to_display
{
    my ($state, $use_rejected) = @_;
    defined $state or die 'no state!';
    my %error = (
        wrong_answer =>          $state == $cats::st_wrong_answer,
        presentation_error =>    $state == $cats::st_presentation_error,
        time_limit_exceeded =>   $state == $cats::st_time_limit_exceeded,                                
        memory_limit_exceeded => $state == $cats::st_memory_limit_exceeded,
        runtime_error =>         $state == $cats::st_runtime_error,
        compilation_error =>     $state == $cats::st_compilation_error,
    );
    (
        not_processed =>         $state == $cats::st_not_processed,
        unhandled_error =>       $state == $cats::st_unhandled_error,
        install_processing =>    $state == $cats::st_install_processing,
        testing =>               $state == $cats::st_testing,
        accepted =>              $state == $cats::st_accepted,
        ($use_rejected ? (rejected => 0 < grep $_, values %error) : %error),
        security_violation =>    $state == $cats::st_security_violation,
        ignore_submit =>         $state == $cats::st_ignore_submit,
    );
}


sub balance_brackets
{
    my $text = shift;
    my @extr = extract_bracketed($text, '()');
    $extr[0];
}


sub balance_tags
{
    my ($text, $tag1, $tag2) = @_;
    my @extr = extract_tagged($text, $tag1, $tag2, undef);
    $extr[0];
}


sub source_hash
{
    Digest::MD5::md5_hex(Encode::encode_utf8($_[0]));
}


sub param_on
{
    return (CGI::param($_[0]) || '') eq 'on';
}


1;
