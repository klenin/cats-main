package CATS::Contest;

use strict;
use warnings;

sub database_fields {qw(
    id title
    start_date finish_date freeze_date defreeze_date
    closed penalty ctype rules max_reqs
    is_official run_all_tests
    show_all_tests show_test_resources show_checker_comment show_packages
    local_only is_hidden
)}

use fields (database_fields(), qw(server_time time_since_start time_since_finish time_since_defreeze));

use lib '..';
use CATS::DB;

sub new
{
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}


sub load
{
    my ($self, $cid) = @_;
    my $all_fields = [
        database_fields(),
        'CURRENT_TIMESTAMP AS server_time',
        map "CURRENT_TIMESTAMP - ${_}_date AS time_since_$_", qw(start finish defreeze)
    ];
    my $r;
    if ($cid)
    {
        $r = CATS::DB::select_row('contests', $all_fields, { id => $cid });
    }
    unless ($r)
    {
        # По умолчанию выбираем тренировочный турнир
        $r = CATS::DB::select_row('contests', $all_fields, { ctype => 1 });
    }
    $r or die 'No contest';
    @{%$self}{keys %$r} = values %$r; 
}


sub is_practice
{
    my ($self) = @_;
    defined $self->{ctype} && $self->{ctype} == 1;
}


sub has_started
{
    my ($self, $virtual_time_offset) = @_;
    $self->{time_since_start} >= ($virtual_time_offset || 0);
}


sub current_official
{
    $dbh->selectrow_hashref(qq~
        SELECT id, title FROM contests
            WHERE CURRENT_TIMESTAMP BETWEEN start_date AND finish_date AND is_official = 1~);
}


1;
