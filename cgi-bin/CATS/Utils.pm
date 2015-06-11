package CATS::Utils;

use strict;
use warnings;

BEGIN {
    use Exporter;

    no strict;
    @ISA = qw(Exporter);
    @EXPORT = qw(
        blob_mimetype
        coalesce
        mode_str
        file_type
        file_type_long
        chop_str
        split_fname
        untabify
        unquote
        escape_xml
        url_function
        state_to_display
        source_hash
        date_to_iso
        encodings
        source_encodings
    );

    %EXPORT_TAGS = (all => [@EXPORT]);
}

use Text::Balanced qw(extract_tagged extract_bracketed);
use Digest::MD5;
use Fcntl ':mode';

use constant {
    S_IFGITLINK => 0160000,
};


sub coalesce { defined && return $_ for @_ }


# submodule/subproject, a commit object reference
sub S_ISGITLINK
{
    my $mode = shift;

    return (($mode & S_IFMT) == S_IFGITLINK)
}

# mimetype related functions

sub mimetype_guess_file
{
    my ($filename, $mimemap) = @_;
    -r $mimemap or return undef;

    my %mimemap;
    open (my $mh, '<', $mimemap) or return undef;
    while (<$mh>) {
        next if m/^#/; # skip comments
        my ($mimetype, @exts) = split(/\s+/);
        foreach my $ext (@exts) {
            $mimemap{$ext} = $mimetype;
        }
    }
    close($mh);

    $filename =~ /\.([^.]*)$/;
    return $mimemap{$1};
}

sub mimetype_guess
{
    my $filename = shift;
    my $mime;
    $filename =~ /\./ or return undef;

    $mime ||= mimetype_guess_file($filename, '/etc/mime.types');
    return $mime;
}

sub blob_mimetype
{
    my ($fd, $filename) = @_;

    if ($filename) {
        my $mime = mimetype_guess($filename);
        $mime and return $mime;
    }

    # just in case
    return 'text/plain' unless $fd;

    if (-T $fd) {
        return 'text/plain';
    } elsif (! $filename) {
        return 'application/octet-stream';
    } elsif ($filename =~ m/\.png$/i) {
        return 'image/png';
    } elsif ($filename =~ m/\.gif$/i) {
        return 'image/gif';
    } elsif ($filename =~ m/\.jpe?g$/i) {
        return 'image/jpeg';
    } else {
        return 'application/octet-stream';
    }
}


# convert file mode in octal to symbolic file mode string
sub mode_str
{
    my $mode = oct shift;

    if (S_ISGITLINK($mode)) {
        return 'm---------';
    } elsif (S_ISDIR($mode & S_IFMT)) {
        return 'drwxr-xr-x';
    } elsif (S_ISLNK($mode)) {
        return 'lrwxrwxrwx';
    } elsif (S_ISREG($mode)) {
        # git cares only about the executable bit
        if ($mode & S_IXUSR) {
            return '-rwxr-xr-x';
        } else {
            return '-rw-r--r--';
        };
    } else {
        return '----------';
    }
}


sub file_type
{
    my $mode = shift;

    if ($mode !~ m/^[0-7]+$/) {
        return $mode;
    } else {
        $mode = oct $mode;
    }

    if (S_ISGITLINK($mode)) {
        return "submodule";
    } elsif (S_ISDIR($mode & S_IFMT)) {
        return "directory";
    } elsif (S_ISLNK($mode)) {
        return "symlink";
    } elsif (S_ISREG($mode)) {
        return "file";
    } else {
        return "unknown";
    }
}


# convert file mode in octal to file type description string
sub file_type_long
{
    my $mode = shift;

    if ($mode !~ m/^[0-7]+$/) {
        return $mode;
    } else {
        $mode = oct $mode;
    }

    if (S_ISGITLINK($mode)) {
        return "submodule";
    } elsif (S_ISDIR($mode & S_IFMT)) {
        return "directory";
    } elsif (S_ISLNK($mode)) {
        return "symlink";
    } elsif (S_ISREG($mode)) {
        if ($mode & S_IXUSR) {
            return "executable";
        } else {
            return "file";
        };
    } else {
        return "unknown";
    }
}


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

# escape tabs (convert tabs to spaces)
sub untabify
{
    my $line = shift;

    while ((my $pos = index($line, "\t")) != -1) {
        if (my $count = (8 - ($pos % 8))) {
            my $spaces = ' ' x $count;
            $line =~ s/\t/$spaces/;
        }
    }

    return $line;
}

# git may return quoted and escaped filenames
sub unquote
{
    my $str = shift;

    sub unq {
        my $seq = shift;
        my %es = ( # character escape codes, aka escape sequences
            't' => "\t",   # tab            (HT, TAB)
            'n' => "\n",   # newline        (NL)
            'r' => "\r",   # return         (CR)
            'f' => "\f",   # form feed      (FF)
            'b' => "\b",   # backspace      (BS)
            'a' => "\a",   # alarm (bell)   (BEL)
            'e' => "\e",   # escape         (ESC)
            'v' => "\013", # vertical tab   (VT)
        );

        if ($seq =~ m/^[0-7]{1,3}$/) {
            # octal char sequence
            return chr(oct($seq));
        } elsif (exists $es{$seq}) {
            # C escape sequence, aka character escape code
            return $es{$seq};
        }
        # quoted ordinary character
        return $seq;
    }

    if ($str =~ m/^"(.*)"$/) {
        # needs unquoting
        $str = $1;
        $str =~ s/\\([^0-7]|[0-7]{1,3})/unq($1)/eg;
    }
    return $str;
}

# Try to chop given string on a word boundary between position
# $len and $len+$add_len. If there is no word boundary there,
# chop at $len+$add_len. Do not chop if chopped part plus ellipsis
# (marking chopped part) would be longer than given string.
sub chop_str
{
    my $str = shift;
    my $len = shift;
    my $add_len = shift || 10;
    my $where = shift || 'right'; # 'left' | 'center' | 'right'

    # Make sure perl knows it is utf8 encoded so we don't
    # cut in the middle of a utf8 multibyte char.
    # $str = to_utf8($str);
    $str = Encode::decode_utf8($str);

    # allow only $len chars, but don't cut a word if it would fit in $add_len
    # if it doesn't fit, cut it if it's still longer than the dots we would add
    # remove chopped character entities entirely

    # when chopping in the middle, distribute $len into left and right part
    # return early if chopping wouldn't make string shorter
    if ($where eq 'center') {
        return $str if ($len + 5 >= length($str)); # filler is length 5
        $len = int($len/2);
    } else {
        return $str if ($len + 4 >= length($str)); # filler is length 4
    }

    # regexps: ending and beginning with word part up to $add_len
    my $endre = qr/.{$len}\w{0,$add_len}/;
    my $begre = qr/\w{0,$add_len}.{$len}/;

    if ($where eq 'left') {
        $str =~ m/^(.*?)($begre)$/;
        my ($lead, $body) = ($1, $2);
        if (length($lead) > 4) {
            $lead = " ...";
        }
        return "$lead$body";

    } elsif ($where eq 'center') {
        $str =~ m/^($endre)(.*)$/;
        my ($left, $str)  = ($1, $2);
        $str =~ m/^(.*?)($begre)$/;
        my ($mid, $right) = ($1, $2);
        if (length($mid) > 5) {
            $mid = " ... ";
        }
        return "$left$mid$right";

    } else {
        $str =~ m/^($endre)(.*)$/;
        my $body = $1;
        my $tail = $2;
        if (length($tail) > 4) {
            $tail = "... ";
        }
        return "$body$tail";
    }
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
        idleness_limit_exceeded=>$state == $cats::st_idleness_limit_exceeded,
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


sub date_to_iso {
    $_[0] =~ /^\s*(\d+)\.(\d+)\.(\d+)\s+(\d+):(\d+)\s*$/;
    "$3$2$1T$4${5}00";
}

sub encodings { {'UTF-8' => 1, 'WINDOWS-1251' => 1, 'KOI8-R' => 1, 'CP866' => 1, 'UCS-2LE' => 1} }

sub source_encodings
{
    [ map {{ enc => $_, selected => $_ eq $_[0] }} sort keys %{encodings()} ];
}

1;
