package CATS::Problem::Source::PlainFiles;

use strict;
use warnings;

use File::Spec;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);

use CATS::BinaryFile;

use base qw(CATS::Problem::Source::Base);

sub new
{
    my ($class, %opts) = @_;
    $opts{dir} or die('The directory is not specified');
    bless \%opts => $class;
}

sub open_directory
{
    my $self = shift;
    opendir(my $dh, $self->{dir}) or $self->error("Cannot open dir: $!");
    return $dh;
}

sub get_zip
{
    my $self = shift;
    my $zip = Archive::Zip->new;
    $zip->addTree($self->{dir}, '', sub { $_ !~ m[/(.git/|.git$)]; });
    open my $fh, '>', \my $content or die "Cannot open filehandle to string: $!";
    my $result = $zip->writeToFileHandle($fh);
    die "Write to filehandle error: $result" unless $result == AZ_OK;
    return $content;
}

sub init { }

sub find_members
{
    my ($self, $regexp) = @_;
    {
        my $dh = $self->open_directory;
        return grep /$regexp/, readdir($dh);
    }
}

sub read_member
{
    my ($self, $name, $msg) = @_;
    my $fname = File::Spec->catfile($self->{dir}, $name);
    $self->error($msg) if ! -e $fname;
    CATS::BinaryFile::load($fname, \my $content);
    return $content;
}

sub finalize
{
    # TODO: needed some changes in architecture
    my ($self, $dbh, $repo, $problem, $message, $is_amend, $repo_id, $sha) = @_;
    $repo->add()->commit($self->{problem}{author}, $message, $is_amend);
}


1;
