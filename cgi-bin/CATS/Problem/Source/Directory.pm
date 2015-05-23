package CATS::Problem::Source::Directory;

use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir tempfile);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);

use CATS::BinaryFile;

my $tmp_dir_template = 'zipXXXXXX';

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

sub get_absoulte_file_path
{
    my ($self, $dir, $fname) = @_;
    my ($volume, $directory) = File::Spec->splitpath($dir, 1);
    return File::Spec->catpath($volume, $directory, $fname);
}

sub get_zip
{
    my $self = shift;
    my $dh = $self->open_directory;
    my $zip = Archive::Zip->new;
    while (readdir $dh) {
        next if $_ =~ m/^\./;
        my $f = $self->get_absoulte_file_path($self->{dir}, $_);
        if (-d $f) {
            $zip->addTree($f, $_);
        } else {
            $zip->addFile($f, $_);
        }
    }
    close $dh;
    (undef, my $fname) = tempfile(OPEN => 0);
    die "Write error zip to temporary file" unless $zip->writeToFileNamed($fname) == AZ_OK;
    my $content;
    CATS::BinaryFile::load($fname, \$content) or $self->{logger}->error("open temporary zip failed: $!");
    return $content;
}

sub init { }


sub find_members
{
    my ($self, $regexp) = @_;
    my $dh = $self->open_directory;
    my @members = grep /$regexp/, readdir($dh);
    closedir($dh);
    return @members;
}


sub read_member
{
    my ($self, $name, $msg) = @_;
    my $fname = $self->get_absoulte_file_path($self->{dir}, $name);
    $self->error($msg) if ! -e $fname;
    my $content;
    CATS::BinaryFile::load($fname, \$content);
    return $content;
}


sub finalize { }


1;
