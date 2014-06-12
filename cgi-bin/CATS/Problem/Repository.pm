package CATS::Problem::Repository;

use strict;
use warnings;
use POSIX qw( strftime );
use File::Temp qw ( tempdir );
use Scalar::Util qw( blessed );
use Archive::Zip qw( :ERROR_CODES );
use File::Copy::Recursive qw( dircopy );
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
    $zip->extractTree('', $path) == AZ_OK or die "can't extract '$zip_name' to $path\n";
}


sub new
{
    my $class = shift;

    my %opts = @_;
    $opts{git_dir} = "$opts{dir}.git" if !exists $opts{git_dir};

    return blessed $class ? $class : bless \%opts => $class;
}


sub git
{
    my ($self, $git_tail) = @_;
    return `git --git-dir=$self->{git_dir} --work-tree=$self->{dir} $git_tail`;
}


sub log
{
    my $self = shift;
    my %opts = @_;
    my $s = Encode::decode_utf8(
        join '', $self->git("log -z --format=format:'h:%h%nc:%H%na:%an%nae:%ae%nd:%at%nm:%B' " . (exists $opts{sha} ? $opts{sha} : '')));
    my $log_part = sub()
    {
        my ($ch, $l) = @_;
        $l =~ m/$ch:(.*)/;
        return $1;
    };
    my @out = ();
    foreach my $log (split "\0", $s) {
        my $message = $log =~ m/m:(.*)/s ? $1 : '';
        my $sha = $log_part->('c', $log);
        push @out, {
            sha => $sha,
            abbreviated_sha => $log_part->('h', $log),
            date => strftime("%d.%m.%Y %H:%M", gmtime($log_part->('d', $log))),
            author => $log_part->('a', $log),
            author_email => $log_part->('ae', $log),
            message => $message
        };
    }
    return \@out;
}


sub commit_info
{
    my ($self, $sha) = shift;
    return Encode::decode_utf8(scalar $self->git("show $sha"));
}


sub new_repo
{
    my ($self, $path, $problem, %opts) = @_;
    my $repo_name = $path . "$problem->{id}/";
    $self = $self->new(dir => $repo_name);
    mkdir $repo_name;
    if (exists $opts{from}) {
        $opts{from} = "$path$opts{from}/";
        $self->move_history(%opts);
    }
    else {
        $self->git('init');
    }
    $self->add($path, $problem, message => (exists $opts{from} ? 'Update task' : 'Initial commit'));
}


sub add
{
    my ($self, $path, $problem, %opts) = @_;
    my $repo_name = $path . "$problem->{id}/";
    $self = $self->new(dir => $repo_name);
    my $tmpdir = tempdir($tmp_template, TMPDIR => 1, CLEANUP => 1);
    extract_zip($tmpdir, $problem->{zip});
    $self->git('rm . -r --ignore-unmatch');
    dircopy($tmpdir, $repo_name);
    $self->commit(exists $opts{message} ? $opts{message} : 'Update task', parse_author($problem->{author}));
}


sub move_history
{
    my ($self, %opts) = @_;
    dircopy($opts{from}, $self->{dir}) or die "Can't copy dir: $!";
    $self->git("reset --hard $opts{sha}");
}


sub commit
{
    my ($self, $message, $author) = @_;
    my ($git_author, $git_author_email) = get_git_author_info($author);
    $self->git("config user.name '$git_author'");
    $self->git("config user.email '$git_author_email'");
    $self->git("add -A");
    die "Nothing to commit, working  directory clean\n" if !$self->git("diff --exit-code --cached");
    $self->git(qq~commit --message="$message"~);
    $self->git("gc");
}


1;
