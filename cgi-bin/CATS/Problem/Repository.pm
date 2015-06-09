package CATS::Problem::Date;

use strict;
use warnings;
use POSIX qw(strftime);

use overload
    'cmp' => sub { $_[0]->{seconds} <=> $_[1]->{seconds} },
    '""' => sub { strftime('%d.%m.%Y %H:%M', gmtime($_[0]->{seconds})) },
;

sub new
{
    my ($class, $seconds) = @_;
    bless { seconds => $seconds }, $class;
}

package CATS::Problem::Repository;

use strict;
use warnings;

use Fcntl ':mode';
use File::Path;
use File::Spec;
use File::Temp qw(tempdir tempfile);
use File::Copy::Recursive qw(dircopy);

use CATS::Problem::Authors;
use CATS::BinaryFile;
use CATS::Utils qw(blob_mimetype untabify unquote mode_str file_type file_type_long chop_str);

my $tmp_template = 'zipXXXXXX';

sub parse_author
{
    my $author = Encode::encode_utf8($_[0]);
    $author = DEFAULT_AUTHOR if !defined $author || $author eq '';
    $author = (split ',', $author)[0];
    chomp $author;
    $author =~ m/^(.*?)\s*(\(.*\))*$/;
    return $1;
}

sub parse_date
{
    my $epoch = shift;
    my $tz = shift || "-0000";

    my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my @days = qw(Sun Mon Tue Wed Thu Fri Sat);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($epoch);
    my %date = (
        hour => $hour,
        minute => $min,
        mday => $mday,
        day => $days[$wday],
        month => $months[$mon],
        rfc2822 => sprintf('%s, %d %s %4d %02d:%02d:%02d +0000', $days[$wday], $mday, $months[$mon], 1900+$year, $hour ,$min, $sec),
        'mday-time' => sprintf('%d %s %02d:%02d', $mday, $months[$mon], $hour, $min),
        'iso-8601'  => sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', 1900+$year, 1+$mon, $mday, $hour ,$min, $sec)
    );

    my ($tz_sign, $tz_hour, $tz_min) = $tz =~ m/^([-+])(\d\d)(\d\d)$/;
    $tz_sign = $tz_sign eq '-' ? -1 : +1;
    my $local = $epoch + $tz_sign *($tz_hour * 60 + $tz_min) * 60;
    ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($local);
    $date{hour_local} = $hour;
    $date{minute_local} = $min;
    $date{tz_local} = $tz;
    $date{'iso-tz'} = sprintf('%04d-%02d-%02d %02d:%02d:%02d %s', 1900+$year, $mon+1, $mday, $hour, $min, $sec, $tz);
    return \%date;
}

# is current raw difftree line of file deletion
sub is_deleted
{
    my ($self, $diffinfo) = @_;
    return defined $diffinfo->{to_id} && $diffinfo->{to_id} eq ('0' x 40);
}

sub diff_line_class
{
    my ($self, $line, $from, $to) = @_;

    # ordinary diff
    my $num_sign = 1;
    # combined diff
    if ($from && $to && ref($from->{href}) eq "ARRAY") {
        $num_sign = scalar @{$from->{href}};
    }

    my @diff_line_classifier = (
        { regexp => qr/^\@\@{$num_sign} /, class => "chunk_header"},
        { regexp => qr/^\\/,               class => "incomplete"  },
        { regexp => qr/^ {$num_sign}/,     class => "ctx" },
        # classifier for context must come before classifier add/rem,
        # or we would have to use more complicated regexp, for example
        # qr/(?= {0,$m}\+)[+ ]{$num_sign}/, where $m = $num_sign - 1;
        { regexp => qr/^[+ ]{$num_sign}/,   class => "add" },
        { regexp => qr/^[- ]{$num_sign}/,   class => "rem" },
    );
    for my $clsfy (@diff_line_classifier) {
        return $clsfy->{class} if ($line =~ $clsfy->{regexp});
    }

    # fallback
    return '';
}

sub format_difftree
{
    my ($self, @difftree) = @_;
    my $difftree = [];
    foreach my $diff (@difftree) {
        my $difftree_line = { file => $diff->{file}};
        my ($to_mode_oct, $to_mode_str, $to_file_type);
        my ($from_mode_oct, $from_mode_str, $from_file_type);
        if ($diff->{to_mode} ne ('0' x 6)) {
            $to_mode_oct = oct $diff->{to_mode};
            if (S_ISREG($to_mode_oct)) { # only for regular file
                $to_mode_str = sprintf('%04o', $to_mode_oct & 0777); # permission bits
            }
            $to_file_type = file_type($diff->{to_mode});
        }
        if ($diff->{from_mode} ne ('0' x 6)) {
            $from_mode_oct = oct $diff->{from_mode};
            if (S_ISREG($from_mode_oct)) { # only for regular file
                $from_mode_str = sprintf('%04o', $from_mode_oct & 0777); # permission bits
            }
            $from_file_type = file_type($diff->{from_mode});
        }

        if ($diff->{status} eq 'A') { # created
            $difftree_line->{status} = 'new';
            $difftree_line->{status_string} = "new $to_file_type";
            $difftree_line->{status_string} .= " with mode: $to_mode_str" if $to_mode_str;
        } elsif ($diff->{status} eq 'D') { # deleted
            $difftree_line->{status} = 'deleted';
            $difftree_line->{status_string} = "deleted $from_file_type";
        } elsif ($diff->{status} eq 'M' || $diff->{status} eq "T") { # modified, or type changed
            $difftree_line->{status} = 'changed';
            if ($diff->{from_mode} != $diff->{to_mode}) {
                $difftree_line->{status_string} = 'changed';
                $difftree_line->{status_string} .= " from $from_file_type to $to_file_type" if $from_file_type ne $to_file_type;
                if (($from_mode_oct & 0777) != ($to_mode_oct & 0777)) {
                    if ($from_mode_str && $to_mode_str) {
                        $difftree_line->{status_string} .= " mode: $from_mode_str->$to_mode_str";
                    } elsif ($to_mode_str) {
                        $difftree_line->{status_string} .= " mode: $to_mode_str";
                    }
                }
            }
        } elsif ($diff->{status} eq 'R' || $diff->{status} eq 'C') { # renamed or copied
            $difftree_line->{file} = $diff->{to_file};
            my $mode_chng = '';
            if ($diff->{from_mode} != $diff->{to_mode}) {
                # mode also for directories, so we cannot use $to_mode_str
                $mode_chng = sprintf(", mode: %04o", $to_mode_oct & 0777);
            }
            my %status_name = ('R' => 'moved', 'C' => 'copied');
            $difftree_line->{status} = $status_name{$diff->{status}};
            $difftree_line->{status_string} = sprintf('%s from %s with %d%%%s', $difftree_line->{status},
                                                        $diff->{from_file}, int $diff->{similarity}, $mode_chng);
        } # we should not encounter Unmerged (U) or Unknown (X) status
        push @{$difftree}, $difftree_line;
    }
    return $difftree;
}

# process patch (diff) line (not to be used for diff headers),
sub format_diff_line
{
    my ($self, $line, $diff_class, $from, $to) = @_;

    chomp $line;
    $line = untabify($line);

    $line = $self->format_unidiff_chunk_header($line, $from, $to) if ($from && $to && $line =~ m/^\@{2} /);

    my $diff_classes = 'diff';
    $diff_classes .= " $diff_class" if ($diff_class);
    return { text => $line, class => $diff_classes };
}

# assumes that $from and $to are defined and correctly filled,
# and that $line holds a line of chunk header for unified diff
sub format_unidiff_chunk_header
{
    my ($self, $line, $from, $to) = @_;

    my ($from_text, $from_start, $from_lines, $to_text, $to_start, $to_lines, $section) =
        $line =~ m/^\@{2} (-(\d+)(?:,(\d+))?) (\+(\d+)(?:,(\d+))?) \@{2}(.*)$/;

    $from_lines = 0 unless defined $from_lines;
    $to_lines   = 0 unless defined $to_lines;

    return { info => "@@ $from_text $to_text @@", section => $section };
}

# Format removed and added line, mark changed part.
# Implementation is based on contrib/diff-highlight
sub format_rem_add_lines_pair
{
    my ($self, $rem, $add) = @_;

    # We need to untabify lines before split()'ing them;
    # otherwise offsets would be invalid.
    chomp $rem;
    chomp $add;
    $rem = untabify($rem);
    $add = untabify($add);

    my @rem = split(//, $rem);
    my @add = split(//, $add);
    # Ignore leading +/- characters for each parent.
    my ($prefix_len, $suffix_len) = (1, 0);
    my ($prefix_has_nonspace, $suffix_has_nonspace);

    my $shorter = (@rem < @add) ? @rem : @add;
    while ($prefix_len < $shorter) {
        last if ($rem[$prefix_len] ne $add[$prefix_len]);

        $prefix_has_nonspace = 1 if ($rem[$prefix_len] !~ /\s/);
        $prefix_len++;
    }

    while ($prefix_len + $suffix_len < $shorter) {
        last if ($rem[-1 - $suffix_len] ne $add[-1 - $suffix_len]);

        $suffix_has_nonspace = 1 if ($rem[-1 - $suffix_len] !~ /\s/);
        $suffix_len++;
    }

    my $diff_rem = $self->format_diff_line($rem, 'rem');
    my $diff_add = $self->format_diff_line($add, 'add');

    # Mark lines that are different from each other, but have some common
    # part that isn't whitespace.  If lines are completely different, don't
    # mark them because that would make output unreadable, especially if
    # diff consists of multiple lines.
    if ($prefix_has_nonspace || $suffix_has_nonspace) {
        $diff_rem->{mark} = [ $prefix_len, @rem - $suffix_len ];
        $diff_add->{mark} = [ $prefix_len, @add - $suffix_len ];
    }

    return ($diff_rem, $diff_add);
}

# HTML-format diff context, removed and added lines.
sub format_ctx_rem_add_lines
{
    my ($self, $ctx, $rem, $add) = @_;
    my (@new_ctx, @new_rem, @new_add);

    if (@$add > 0 && @$add == @$rem) {
        for (my $i = 0; $i < @$add; $i++) {
            my ($line_rem, $line_add) = $self->format_rem_add_lines_pair($rem->[$i], $add->[$i]);
            push @new_rem, $line_rem;
            push @new_add, $line_add;
        }
    } else {
        @new_rem = map { $self->format_diff_line($_, 'rem') } @$rem;
        @new_add = map { $self->format_diff_line($_, 'add') } @$add;
    }

    @new_ctx = map { $self->format_diff_line($_, 'ctx') } @$ctx;

    return (@new_ctx, @new_rem, @new_add);
}

sub format_diff_chunk
{
    my ($self, $from, $to, @chunk) = @_;
    my (@ctx, @rem, @add);

    # The class of the previous line.
    my $prev_class = '';

    return unless @chunk;

    # incomplete last line might be among removed or added lines,
    # or both, or among context lines: find which
    for (my $i = 1; $i < @chunk; $i++) {
        if ($chunk[$i][0] eq 'incomplete') {
            $chunk[$i][0] = $chunk[$i-1][0];
        }
    }

    # guardian
    push @chunk, ['', ''];

    my $result_chunk = { header => undef, lines => []};
    foreach my $line_info (@chunk) {
        my ($class, $line) = @$line_info;

        # print chunk headers
        if ($class && $class eq 'chunk_header') {
            $result_chunk->{header} = $self->format_diff_line($line, $class, $from, $to);
            next;
        }

        ## print from accumulator when have some add/rem lines or end
        # of chunk (flush context lines), or when have add and rem
        # lines and new block is reached (otherwise add/rem lines could
        # be reordered)
        if (!$class || ((@rem || @add) && $class eq 'ctx') ||
            (@rem && @add && $class ne $prev_class)) {
            push @{$result_chunk->{lines}}, $self->format_ctx_rem_add_lines(\@ctx, \@rem, \@add);
            @ctx = @rem = @add = ();
        }

        ## adding lines to accumulator
        # guardian value
        last unless $line;
        # rem, add or change
        if ($class eq 'rem') {
            push @rem, $line;
        } elsif ($class eq 'add') {
            push @add, $line;
        }
        # context line
        if ($class eq 'ctx') {
            push @ctx, $line;
        }

        $prev_class = $class;
    }
    return $result_chunk;
}

# parse extended diff header line, before patch itself
sub format_extended_diff_header_line
{
    my ($self, $line, $diffinfo, $from, $to) = @_;
    # match <path>
    $line .= $from->{file} if $line =~ s!^((copy|rename) from ).*$!$1! && $from->{href};
    $line .= $to->{file} if $line =~ s!^((copy|rename) to ).*$!$1! && $to->{href};

    # match single <mode>
    $line .= sprintf('<span class="info"> (%s)</span>', file_type_long($1)) if $line =~ m/\s(\d{6})$/;
    # match <hash>
    if ($line =~ m/^index [0-9a-fA-F]{40}..[0-9a-fA-F]{40}/) {
        # can match only for ordinary diff
        my ($from_link, $to_link);
        if ($from->{href}) {
            $from_link = substr($diffinfo->{from_id}, 0, 7);
        } else {
            $from_link = '0' x 7;
        }
        if ($to->{href}) {
            $to_link = substr($diffinfo->{to_id}, 0, 7);
        } else {
            $to_link = '0' x 7;
        }
        my ($from_id, $to_id) = ($diffinfo->{from_id}, $diffinfo->{to_id});
        $line =~ s!$from_id\.\.$to_id!$from_link..$to_link!;
    }

    return $line;
}

# format git diff header line, i.e. "diff --(git|combined|cc) ..."
sub format_git_diff_header_line
{
    my ($self, $line, $diffinfo, $from, $to) = @_;

    $line =~ s!^(diff (.*?) )"?a/.*$!$1!;
    $line .= 'a/' . $from->{file};
    $line .= ' b/' . $to->{file};

    return $line;
}

sub format_page_path
{
    my ($self, $name, $type, $hb) = @_;
    my @dirname = split '/', join '', $self->git('rev-parse --show-toplevel');
    my $project = pop @dirname;
    chomp $project;
    my @parts = ({
        name => '',
        file_name => $project,
        hash_base => $hb,
        title => 'tree root',
        type => 'tree'
    });
    if (defined $name) {
        my @dirname = split '/', $name;
        my $basename = pop @dirname;
        my $fullname = '';

        foreach my $dir (@dirname) {
            $fullname .= ($fullname ? '/' : '') . $dir;
            push @parts, {
                type => 'tree',
                name => $fullname,
                file_name => $dir,
                hash_base => $hb,
                title => $fullname,
            };
        }
        if (defined $type && $type eq 'blob') {
            $type = 'raw'
        } elsif (defined $type && $type eq 'tree') {
            $type = 'tree';
        }
        push @parts, {
            type => $type,
            name => $name,
            file_name => $basename,
            hash_base => $hb,
            title => $name,
        };
    }
    return \@parts;
}

# parse line of git-diff-tree "raw" output
sub parse_difftree_raw_line
{
    my ($self, $line) = @_;
    my %res;

    # ':100644 100644 03b218260e99b78c6df0ed378e59ed9205ccc96d 3b93d5e7cc7f7dd4ebed13a5cc1a4ad976fc94d8 M   ls-files.c'
    # ':100644 100644 7f9281985086971d3877aca27704f2aaf9c448ce bc190ebc71bbd923f2b728e505408f5e54bd073a M   rev-tree.c'
    if ($line =~ m/^:([0-7]{6}) ([0-7]{6}) ([0-9a-fA-F]{40}) ([0-9a-fA-F]{40}) (.)([0-9]{0,3})\t(.*)$/) {
        $res{from_mode} = $1;
        $res{to_mode} = $2;
        $res{from_id} = $3;
        $res{to_id} = $4;
        $res{status} = $5;
        $res{similarity} = $6;
        if ($res{status} eq 'R' || $res{status} eq 'C') { # renamed or copied
            ($res{from_file}, $res{to_file}) = map { unquote($_) } split("\t", $7);
        } else {
            $res{from_file} = $res{to_file} = $res{file} = unquote($7);
        }
    }
    # '::100755 100755 100755 60e79ca1b01bc8b057abe17ddab484699a7f5fdb 94067cc5f73388f33722d52ae02f44692bc07490 94067cc5f73388f33722d52ae02f44692bc07490 MR git-gui/git-gui.sh'
    # combined diff (for merge commit)
    elsif ($line =~ s/^(::+)((?:[0-7]{6} )+)((?:[0-9a-fA-F]{40} )+)([a-zA-Z]+)\t(.*)$//) {
        $res{nparents}  = length($1);
        $res{from_mode} = [ split(' ', $2) ];
        $res{to_mode} = pop @{$res{from_mode}};
        $res{from_id} = [ split(' ', $3) ];
        $res{to_id} = pop @{$res{from_id}};
        $res{status} = [ split('', $4) ];
        $res{to_file} = unquote($5);
    }
    # 'c512b523472485aef4fff9e57b229d9d243c967f'
    elsif ($line =~ m/^([0-9a-fA-F]{40})$/) {
        $res{commit} = $1;
    }

    return \%res;
}

# generates _two_ hashes, references to which are passed as 2 and 3 argument
sub parse_from_to_diffinfo
{
    my ($self, $diffinfo, $from, $to) = @_;

    # ordinary (not combined) diff
    $from->{file} = $diffinfo->{from_file};
    $from->{href} = $diffinfo->{status} ne 'A';

    $to->{file} = $diffinfo->{to_file};
    $to->{href} = !$self->is_deleted($diffinfo); # file exists in result
}

# parse from-file/to-file diff header
sub parse_diff_from_to_header
{
    my ($self, $from_line, $to_line, $diffinfo, $from, $to) = @_;
    my $line;
    my $result = '';

    $line = $from_line;
    # no extra formatting for "^--- /dev/null"
    if (!$diffinfo->{nparents}) {
        # ordinary (single parent) diff
        $from->{header} = $line =~ m!^--- "?a/! ? '--- a/' . $from->{file} : $line;
    }
    $line = $to_line;
    # no extra formatting for "^+++ /dev/null"
    $to->{header} = $line =~ m!^\+\+\+ "?b/! ? '+++ b/' . $to->{file} : $line;
}

sub parse_patches
{
    my ($self, $difftree, $lines, $hash, $hash_parent) = @_;

    my $patch_idx = 0;
    my $patch_number = 0;
    my $patch_line;
    my $diffinfo;
    my $to_name;
    my @chunk; # for side-by-side diff
    my @patches = ();

    # skip to first patch
    while ($patch_line = shift @$lines) {
        chomp $patch_line;

        last if ($patch_line =~ m/^diff /);
    }

    my $patch_desc = {from => {}, to => {}};
 PATCH:
    while ($patch_line) {
        # parse "git diff" header line
        if ($patch_line =~ m/^diff --git (\"(?:[^\\\"]*(?:\\.[^\\\"]*)*)\"|[^ "]*) (.*)$/) {
            # $1 is from_name, which we do not use
            $to_name = unquote($2);
            $to_name =~ s!^b/!!;
        } else {
            $to_name = undef;
        }
        $patch_desc->{to_name} = $to_name;

        # advance raw git-diff output if needed
        $patch_idx++ if defined $diffinfo;

        # read and prepare patch information
        $diffinfo = $difftree->[$patch_idx];

        # modifies %from, %to hashes
        $self->parse_from_to_diffinfo($diffinfo, $patch_desc->{from}, $patch_desc->{to});

        # this is first patch for raw difftree line with $patch_idx index
        # we index @$difftree array from 0, but number patches from 1
        $patch_desc->{idx} = $patch_idx + 1;

        # git diff header
        $patch_number++;
        $patch_desc->{header} = $self->format_git_diff_header_line($patch_line, $diffinfo, $patch_desc->{from}, $patch_desc->{to});

        $patch_desc->{extended_header} = [];
    EXTENDED_HEADER:
        while ($patch_line = shift @$lines) {
            chomp $patch_line;

            last EXTENDED_HEADER if ($patch_line =~ m/^--- |^diff /);
            push @{$patch_desc->{extended_header}}, $self->format_extended_diff_header_line($patch_line, $diffinfo, $patch_desc->{from}, $patch_desc->{to});
        }

        # from-file/to-file diff header
        if (!$patch_line) {
            last PATCH;
        }
        next PATCH if $patch_line =~ m/^diff /;

        my $last_patch_line = $patch_line;
        $patch_line = shift @$lines;
        chomp $patch_line;

        $self->parse_diff_from_to_header($last_patch_line, $patch_line, $diffinfo, $patch_desc->{from}, $patch_desc->{to});

        # the patch itself
    LINE:
        $patch_desc->{chunks} = [];
        while ($patch_line = shift @$lines) {
            chomp $patch_line;

            next PATCH if ($patch_line =~ m/^diff /);
            my $class = $self->diff_line_class($patch_line, $patch_desc->{from}, $patch_desc->{to});

            if ($class eq 'chunk_header') {
                push @{$patch_desc->{chunks}}, $self->format_diff_chunk($patch_desc->{from}, $patch_desc->{to}, @chunk);
                @chunk = ();
            }

            push @chunk, [ $class, $patch_line ];
        }
    } continue {
        if (@chunk) {
            push @{$patch_desc->{chunks}}, $self->format_diff_chunk($patch_desc->{from}, $patch_desc->{to}, @chunk);
            @chunk = ();
        }
        push @patches, $patch_desc;
        $patch_desc = {from => {}, to => {}}
    }
    return \@patches;
}

sub parse_commit_text
{
    my ($self, $commit_lines, $withparents) = @_;
    my %co;
    pop @$commit_lines; # Remove '\0'

    @$commit_lines or return;

    my $header = shift @$commit_lines;
    $header =~ m/^[0-9a-fA-F]{40}/ or return;
    ($co{id}, my @parents) = split ' ', $header;

    while (my $line = shift @$commit_lines) {
        last if $line eq "\n";
        if ($line =~ m/^tree ([0-9a-fA-F]{40})$/) {
            $co{tree} = $1;
        } elsif ((!defined $withparents) && ($line =~ m/^parent ([0-9a-fA-F]{40})$/)) {
            push @parents, $1;
        } else {
            foreach my $who (qw(author committer)) {
                if ($line =~ m/^${who} (.*) ([0-9]+) (.*)$/) {
                    $co{"${who}"} = Encode::decode_utf8($1);
                    $co{"${who}_epoch"} = $2;
                    $co{"${who}_tz"} = $3;
                    $co{"${who}_date"} = parse_date($2, $3);
                    $co{"${who}_formatted_ts"} = sprintf(
                        '%s (%02d:%02d %s)',
                        $co{"${who}_date"}->{rfc2822},
                        $co{"${who}_date"}->{hour_local},
                        $co{"${who}_date"}->{minute_local},
                        $co{"${who}_date"}->{tz_local}
                    );
                    if ($co{"${who}"} =~ m/^([^<]+) <([^>]*)>/) {
                        $co{"${who}_name"}  = $1;
                        $co{"${who}_email"} = $2;
                    } else {
                        $co{"${who}_name"} = $co{"${who}"};
                    }
                }
            }
        }
    }
    defined $co{tree} or return;

    $co{parents} = \@parents;
    $co{parent} = $parents[0];

    foreach my $title (@$commit_lines) {
        $title =~ s/^    //;
        if ($title ne '') {
            $co{title} = chop_str($title, 80, 5);
            $co{title_short} = chop_str($title, 50, 5);
            last;
        }
    }
    if (! defined $co{title} || $co{title} eq '') {
        $co{title} = $co{title_short} = '(no commit message)';
    }
    shift @$commit_lines;
    $co{comment_lines} = [];
    foreach my $line (@$commit_lines) {
        chomp $line;
        $line =~ s/^    //;
        push @{$co{comment_lines}}, Encode::decode_utf8($line) if $line ne '';
    }
    return %co;
}

sub commif_diff
{
    my ($self, %co) = @_;
    @{$co{parents}} <= 1 or die 'Too many parents'; # TODO?
    # my $hash_parent_param = @{$co{'parents'}} > 1 ? '--cc' : $co{'parent'} || '--root';
    my $hash_parent_param = $co{parent} || '--root';
    my @lines = map Encode::decode($co{encoding}, $_),
        $self->git("diff-tree -r -M --no-commit-id --patch-with-raw --full-index $hash_parent_param ${co{id}}");
    my @difftree;
    while (scalar @lines) {
        my $line = shift @lines;
        chomp $line;
        # empty line ends raw part of diff-tree output
        last unless $line;
        push @difftree, $self->parse_difftree_raw_line($line);
    }
    my $patches = $self->parse_patches(\@difftree, \@lines, $co{id}, $hash_parent_param);
    return (difftree => $self->format_difftree(@difftree), patches => $patches);
}

sub parse_commit
{
    my ($self, $sha) = @_;
    return $self->parse_commit_text([ $self->git("rev-list --header --max-count=1 $sha") ], 1);
}

sub commit_info
{
    my ($self, $sha, $enc) = @_;
    my %co = $self->parse_commit($sha);
    return { info => \%co, $self->commif_diff(%co, encoding => $enc), log => $self->{log} };
}

# format tree entry (row of git_tree)
sub format_tree_entry
{
    my ($self, $t, $basedir) = @_;
    $t->{mode} = mode_str($t->{mode});
    $t->{size} = $t->{size} if exists $t->{size};
}

sub parse_ls_tree_line
{
    my ($self, $line, $basedir) = @_;
    my %res;

    #'100644 blob 0fa3f3a66fb6a137f6ec2c19351ed4d807070ffa   16717  panic.c'
    $line =~ m/^([0-9]+) (.+) ([0-9a-fA-F]{40}) +(-|[0-9]+)\t(.+)$/s;

    return (
        mode => $1,
        type => $2,
        hash => $3,
        size => $4,
        name => "$basedir$5",
        file_name => $5
    );
}

sub git_get_hash_by_path
{
    my $self = shift;
    my $base = shift;
    my $path = shift || return undef;
    my $type = shift;

    $path =~ s,/+$,,;

    my $line = join '', $self->git("ls-tree $base -- $path");

    if (!defined $line) {
        # there is no tree or hash given by $path at $base
        return undef;
    }

    #'100644 blob 0fa3f3a66fb6a137f6ec2c19351ed4d807070ffa  panic.c'
    $line =~ m/^([0-9]+) (.+) ([0-9a-fA-F]{40})\t/;
    if (defined $type && $type ne $2) {
        # type doesn't match
        return undef;
    }

    return $3;
}

sub tree
{
    my ($self, $hash_base, $file, $enc) = @_;
    my $hash = defined $file ? $self->git_get_hash_by_path($hash_base, $file, 'tree') : $hash_base;

    my $basedir = '';
    if (defined $file) {
        $basedir = $file;
        if ($basedir ne '' && substr($basedir, -1) ne '/') {
            $basedir .= '/';
        }
    }

    my @entries = ();
    if (defined $hash_base && defined $file && $file =~ m![^/]+$!) {
        my $up = $file;
        $up =~ s!/?[^/]+$!!;
        undef $up unless $up;
        push @entries, {
            mode => mode_str('040000'),
            size => '',
            hash => $hash_base,
            type => 'tree',
            name => $up,
            file_name => '..'
        };
    }

    foreach my $line (map { chomp; $_ } split "\0", join '', $self->git("ls-tree -z -l $hash")) {
        my %t = $self->parse_ls_tree_line($line, $basedir);
        $self->format_tree_entry(\%t, '');
        push @entries, \%t;
    }

    my %co = $self->parse_commit($hash_base);
    return {
        entries => \@entries,
        commit => \%co,
        basedir => $basedir,
        paths => $self->format_page_path($file, 'tree', $hash_base),
        latest_sha => $self->get_latest_master_sha,
        is_remote => $self->get_remote_url,
    };
}

sub blob
{
    my ($self, $hash_base, $file, $enc) = @_;
    die "No file name defined" if !defined $file;
    die 'No encoding defined' if !defined $enc;

    my $hash = $self->git_get_hash_by_path($hash_base, $file, 'blob');

    my $fd = $self->git_handler("cat-file blob $hash");

    my $result = {
        lines => [],
        paths => $self->format_page_path($file, 'blob', $hash_base),
        latest_sha => $self->get_latest_master_sha,
        is_remote => $self->get_remote_url,
    };

    my $mimetype = blob_mimetype($fd, $file);
    # use 'blob_plain' (aka 'raw') view for files that cannot be displayed
    if ($mimetype !~ m!^(?:text/|image/(?:gif|png|jpeg)|application/xml$)! && -B $fd) {
        close $fd;
        return $result;
    }

    if ($mimetype =~ m!^image/!) {
        my @parts = split CATS::Config::cats_dir, $self->{dir} . $file;
        $result->{image} = $parts[1];
    } else {
        my $nr;
        while (my $line = <$fd>) {
            chomp $line;
            $line = Encode::decode($enc, $line);
            $line = untabify($line);
            $nr++;
            push @{$result->{lines}}, {number => $nr, text => $line};
        }
    }
    close $fd;

    return $result;
}

sub raw
{
    my ($self, $hash_base, $file) = @_;
    die "No file name defined" if !defined $file;

    my $hash = $self->git_get_hash_by_path($hash_base, $file, 'blob');

    my $fd = $self->git_handler("cat-file blob $hash");
    my $mimetype = blob_mimetype($fd, $file);
    my $content = join '', <$fd>;
    close $fd;

    return {
        type => $mimetype,
        content => $content,
        latest_sha => $self->get_latest_master_sha,
    };
}

sub new
{
    my ($class, %opts) = @_;
    $opts{dir} //= '';
    $opts{git_dir} //= "$opts{dir}.git";
    return bless \%opts => $class;
}

sub set_repo
{
    my ($self, $dir) = @_;
    $self->{dir} = $dir;
    $self->{git_dir} = "$dir.git";
    return $self;
}

sub exec_or_die
{
    # Apache subprocces, capture both stdout and stderr.
    my @r = `$_[0] 2>&1`;
    die join "\n", $_[0], @r, "Error $?" if $?;
    @r;
}

sub git
{
    my ($self, $git_tail) = @_;
    my @lines = exec_or_die("git --git-dir=$self->{git_dir} --work-tree=$self->{dir} $git_tail");
    $self->{logger}->note(join "\n", @lines) if exists $self->{logger};
    return @lines;
}

sub git_handler
{
    my ($self, $git_tail) = @_;
    open my $fd, '-|', "git --git-dir=$self->{git_dir} --work-tree=$self->{dir} $git_tail" or die("cannot run git command: $!");
    return $fd;
}

sub find_files
{
    my ($self, $regexp) = @_;
    my @files = $self->git('ls-tree HEAD --name-only');
    chomp $_ foreach @files;
    return grep /$regexp/, @files;
}

sub log
{
    my ($self, %opts) = @_;
    my $sha = $opts{sha} // '';
    my $max_count = $opts{max_count} ? "--max-count=$opts{max_count} " : '';
    my $s = Encode::decode_utf8(join '', $self->git("log -z $max_count--format=format:'%H||%h||%an||%ae||%at||%ct||%B' $sha"));
    my @out = ();
    foreach my $log (split "\0", $s) {
        my ($sha, $abrev_sha, $author, $email, $adate, $cdate, $message) = split /\|\|/, $log;
        my ($subject, $body) = split "\n\n", $message, 2;
        push @out, {
            sha => $sha,
            abbreviated_sha => $abrev_sha,
            subject => $subject,
            body => $body,
            author => $author,
            author_email => $email,
            author_date => CATS::Problem::Date->new($adate), # TODO: Figure out locales.
            committer_date => CATS::Problem::Date->new($cdate),
        };
    }
    return \@out;
}

sub archive
{
    my ($self, $tree_id) = @_;
    if (!$tree_id) {
        $tree_id = join '', $self->git('log --format=%H -1');
        chomp $tree_id;
    }
    (undef, my $fname) = tempfile(OPEN => 0, DIR => tempdir($tmp_template, TMPDIR => 1, CLEANUP => 1));
    $self->git("archive --format=zip $tree_id --output=$fname");
    return ($fname, $tree_id);
}

sub new_repo
{
    my ($self, $problem, %opts) = @_;
    mkdir $self->{dir} or die "Unable to create repo dir: $!";
    if (exists $opts{from}) {
        $self->move_history(%opts);
    }
    else {
        $self->git('init');
    }
    $self->add($problem, message => (exists $opts{from} ? 'Update task' : 'Initial commit'));
    return $self;
}

sub get_dir { $_[0]->{dir} }

sub delete
{
    my ($self) = @_;
    rmtree($self->{dir}) or warn q~Git repository doesn't exist~;
}

sub init
{
    my ($self, %opts) = @_;
    mkdir $self->{dir} or die "Unable to create repo dir: $!";
    $self->git('init');
    return $self;
}

sub rm
{
    my ($self, @args) = @_;
    $self->git('rm ' . join(' ', @args));
    return $self;
}

sub add
{
    my $self = shift;
    $self->git('add -A');
    return $self;
}

sub replace_file_content
{
    my ($self, $file, $content) = @_;
    CATS::BinaryFile::save(File::Spec->catfile($self->{dir}, $file), $content);
}

sub move_history
{
    my ($self, %opts) = @_;
    rmtree $self->{dir};
    mkdir $self->{dir};
    dircopy($opts{from}, $self->{dir}) or die "Can't copy dir: $!";
    $self->git("reset --hard $opts{sha}");
    return $self;
}

sub get_remote_url
{
    my $self = shift;
    my ($remote_url) = eval { $self->git('config remote.origin.url'); };
    chomp $remote_url;
    return $remote_url;
}

sub get_latest_master_sha
{
    my $self = shift;
    my $sha = join '', $self->git('rev-parse master');
    chomp $sha;
    return $sha;
}

sub is_remote
{
    my $remote_url = $_[0]->get_remote_url;
    return defined $remote_url && $remote_url ne '';
}

sub reset
{
    my ($self, $arg) = @_;
    $self->git("reset $arg");
    return $self;
}

sub checkout
{
    my ($self, $what) = @_;
    $what //= '.';
    $self->git("checkout $what");
    return $self;
}

sub commit
{
    my ($self, $problem_author, $message, $is_amend) = @_;
    if (!($self->{author_name} && $self->{author_email})) {
        my ($git_author_name, $git_author_email) = get_git_author_info(parse_author($problem_author));
        $self->{author_name} ||= $git_author_name;
        $self->{author_email} ||= $git_author_email;
        $self->{logger}->warning('git user data is not correctly configured.') if exists $self->{logger};
    }
    $self->git(qq~config user.name "$self->{author_name}"~);
    $self->git(qq~config user.email "$self->{author_email}"~);
    my $args = $is_amend ? '--amend' : '';
    $self->git(qq~commit $args -m "$message"~);
    $self->git('gc');
    return $self;
}

sub clone
{
    my ($link, $dir) = @_;
    my @lines = exec_or_die("git clone $link $dir");
    return (CATS::Problem::Repository->new(dir => $dir), @lines);
}

sub pull
{
    my ($self, $remote_url) = @_;
    $self->git("fetch $remote_url");
    $self->git('merge origin/master');
}

1;
