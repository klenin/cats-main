package CATS::Problem::ImportSource::DB;

use strict;
use warnings;

use CATS::DB;
use Data::Dumper;

use base qw(CATS::Problem::ImportSource::Base);

sub get_sources
{
    my ($self, $guid) = @_;
    $dbh->selectrow_array(qq~SELECT id, stype FROM problem_sources WHERE guid = ?~, undef, $guid);
}

sub get_guids
{
    my ($self, $guid) = @_;
    @{$dbh->selectcol_arrayref(qq~SELECT guid FROM problem_sources WHERE guid LIKE ? ESCAPE '\\'~, undef, $guid)};
}

1;
