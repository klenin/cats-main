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
use File::Temp qw(tempdir);
use Archive::Zip qw(:ERROR_CODES);
use File::Path;
use File::Copy::Recursive qw(dircopy);
use CATS::Problem::Authors;

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

sub extract_zip
{
    my ($path, $zip_name) = @_;
    my $zip = Archive::Zip->new();
    $zip->read($zip_name) == AZ_OK or die "open zip '$zip_name' failed!\n";
    $zip->extractTree('', "$path/") == AZ_OK or die "can't extract '$zip_name' to $path\n";
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

sub git
{
    my ($self, $git_tail) = @_;
    my @lines = `git --git-dir=$self->{git_dir} --work-tree=$self->{dir} $git_tail`;  #Apache sub procces
    $self->{logger}->note(join '', @lines) if exists $self->{logger};
    return @lines;
}

sub log
{
    my ($self, %opts) = @_;
    my $sha = $opts{sha} // '';
    my $s = Encode::decode_utf8(join '', $self->git("log -z --format=format:'%H||%h||%an||%ae||%at||%ct||%B' $sha"));
    my @out = ();
    foreach my $log (split "\0", $s) {
        my ($sha, $abrev_sha, $author, $email, $adate, $cdate, $message) = split /\|\|/, $log;
        my @comment_lines = split "\n\n", $message;
        my $subject = shift @comment_lines;
        push @out, {
            sha => $sha,
            abbreviated_sha => $abrev_sha,
            subject => $subject,
            body => join("\n\n", @comment_lines),
            author => $author,
            author_email => $email,
            author_date => CATS::Problem::Date->new($adate), # TODO: Figure out locales.
            committer_date => CATS::Problem::Date->new($cdate),
        };
    }
    return \@out;
}

sub commit_info
{
    my ($self, $sha) = @_;
    return Encode::decode_utf8(join '', $self->git("show $sha"));
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

sub delete
{
    my ($self) = @_;
    die "Git repository doesn't exist" unless -d $self->{dir};
    rmtree($self->{dir});
}

sub init
{
    my ($self, $problem, %opts) = @_;
    mkdir $self->{dir} or die "Unable to create repo dir: $!";
    $self->git('init');
    $self->add($problem, message => 'Initial commit');
    return $self;
}

sub add
{
    my ($self, $problem, %opts) = @_;
    my $tmpdir = tempdir($tmp_template, TMPDIR => 1, CLEANUP => 1);
    extract_zip($tmpdir, $problem->{zip});
    $self->git('rm . -r --ignore-unmatch');
    dircopy($tmpdir, $self->{dir});
    if (!($self->{author_name} && $self->{author_email})) {
        my ($git_author_name, $git_author_email) = get_git_author_info(parse_author($problem->{author}));
        $self->{author_name} ||= $git_author_name;
        $self->{author_email} ||= $git_author_email;
        $self->{logger}->warning('git user data is not correctly configured.') if exists $self->{logger};
    }
    $self->commit($opts{message} || 'Update task');
    return $self;
}

sub move_history
{
    my ($self, %opts) = @_;
    mkdir $self->{dir} unless -d $self->{dir};
    dircopy($opts{from}, $self->{dir}) or die "Can't copy dir: $!";
    $self->git("reset --hard $opts{sha}");
    return $self;
}

sub commit
{
    my ($self, $message) = @_;
    $self->git(qq~config user.name "$self->{author_name}"~);
    $self->git(qq~config user.email "$self->{author_email}"~);
    $self->git('add -A');
    $self->git(qq~commit -m "$message"~);
    $self->git('gc');
    return $self;
}

1;
