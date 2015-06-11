package CATS::Problem::Source::Git;

use strict;
use warnings;

use File::Temp qw(tempdir);
use File::Copy::Recursive qw(dircopy);

use CATS::BinaryFile;
use CATS::Problem::Repository;

use base qw(CATS::Problem::Source::Base);

my $tmp_repo_template = 'repoXXXXXX';

sub new
{
    my ($class, $link, $logger) = @_;
    defined $link or die('No remote url specified!');
    defined $logger or die('No logger!');
    my %opts = (
        dir => undef,
        repo => undef,
        link => $link,
        logger => $logger,
    );
    return bless \%opts => $class;
}

sub get_zip
{
    my $self = shift;
    my ($fname, $tree_id) = $self->{repo}->archive;
    my $zip;
    CATS::BinaryFile::load($fname, \$zip) or $self->{logger}->error("getting zip archive failed: $!");
    return $zip;
}

sub init
{
    my $self = shift;
    my $tmpdir = tempdir($tmp_repo_template, TMPDIR => 1, CLEANUP => 1);
    $self->{dir} = $tmpdir;
    ($self->{repo}, my @log) = CATS::Problem::Repository::clone($self->{link}, "$tmpdir/");
    $self->{logger}->note(join "\n", @log);
}

sub find_members
{
    my ($self, $regexp) = @_;
    return $self->{repo}->find_files($regexp);
}

sub read_member
{
    my ($self, $name, $msg) = @_;
    my $content;
    CATS::BinaryFile::load($self->{repo}->get_dir . $name, \$content);
    return $content;
}

sub finalize
{
    my ($self, $dbh, $repo, $problem, $message, $is_amend, $repo_id, $sha) = @_;

    dircopy($self->{dir}, $repo->get_dir);
}


1;
