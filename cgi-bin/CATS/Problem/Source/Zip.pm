package CATS::Problem::Source::Zip;

use strict;
use warnings;

use File::Temp qw(tempdir);
use File::Copy::Recursive qw(dirmove);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);

use CATS::BinaryFile;

use base qw(CATS::Problem::Source::Base);

my $tmp_template = 'zipXXXXXX';

sub new
{
    my ($class, $fname, $logger) = @_;
    $fname or die('No filename!');
    $logger or die('No logger!');
    my %opts = (
        zip => undef,
        fname => $fname,
        logger => $logger
    );
    bless \%opts => $class;
}

sub get_zip
{
    my $self = shift;
    my $zip;
    CATS::BinaryFile::load($self->{fname}, \$zip) or $self->{logger}->error("open '$self->{fname}' failed: $!");
    return $zip;
}

sub init
{
    my $self = shift;
    $self->{zip} = Archive::Zip->new();
    $self->{zip}->read($self->{fname}) == AZ_OK
        or $self->{logger}->error("read '$self->{fname}' failed -- probably not a zip archive");
}

sub find_members
{
    my ($self, $regexp) = @_;
    return map { $_->fileName() } $self->{zip}->membersMatching($regexp);
}

sub read_member
{
    my ($self, $name, $msg) = @_;
    my $member = $self->{zip}->memberNamed($name) or $self->{logger}->error($msg);

    $member->desiredCompressionMethod(COMPRESSION_STORED);
    my $status = $member->rewindData();
    $status == AZ_OK or $self->{logger}->error("code $status");

    my $data = '';
    while (!$member->readIsDone()) {
        (my $buffer, $status) = $member->readChunk();
        $status == AZ_OK || $status == AZ_STREAM_END or $self->error("code $status");
        $data .= $$buffer;
    }
    $member->endRead();

    return $data;
}

sub extract
{
    my ($self, $repo) = @_;
    my $tmpdir = tempdir($tmp_template, TMPDIR => 1, CLEANUP => 1);
    $self->{zip}->extractTree('', "$tmpdir/") == AZ_OK or die "can't extract '$self->{zip}' to $tmpdir\n";
    $repo->rm(qw/. -r --ignore-unmatch/);
    dirmove($tmpdir, $repo->get_dir);
    return $self;
}

sub finalize
{
    my ($self, $dbh, $repo, $problem, $message, $is_amend, $repo_id, $sha) = @_;

    if ($problem->{replace}) {
        $repo->init unless -d $repo->{dir}; # Some repos were not created during mass import.
        $repo->move_history(from => $CATS::Config::repos_dir . "/$repo_id/", sha => $sha) unless $repo_id == $problem->{id};
        $self->extract($repo);
        $message ||= 'Update task';
    } else {
        $repo->init;
        $self->extract($repo);
        $message ||= 'Initial commit';
    }

    $repo->add()->commit($problem->{description}{author}, $message, $is_amend);

    if ($problem->{replace} && $repo_id != $problem->{id}) {
        $dbh->do(qq~
            UPDATE problems SET repo = ?, commit_sha = ? WHERE id = ?~, undef,
                undef, undef, $problem->{id});
    }
}


1;
