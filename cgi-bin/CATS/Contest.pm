package CATS::Contest;

use strict;
use warnings;

sub database_fields {qw(
    id title
    start_date finish_date freeze_date defreeze_date
    closed penalty ctype rules max_reqs
    is_official run_all_tests
    show_all_tests show_test_resources show_checker_comment show_packages show_test_data
    local_only is_hidden
)}

use fields (database_fields(), qw(server_time time_since_start time_since_finish time_since_defreeze));

use CATS::Constants;
use CATS::DB;

sub new
{
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}

sub load
{
    my ($self, $cid, $fields) = @_;
    $fields //= [
        database_fields(),
        'CURRENT_TIMESTAMP AS server_time',
        map "CAST(CURRENT_TIMESTAMP - ${_}_date AS DOUBLE PRECISION) AS time_since_$_",
            qw(start finish defreeze)
    ];
    my $r = $cid ? CATS::DB::select_row('contests', $fields, { id => $cid }) : undef;
    # Choose training contest by default.
    $r or $r = CATS::DB::select_row('contests', $fields, { ctype => 1 }) or die 'No contest';
    @$self{keys %$r} = values %$r;
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

sub used_problem_codes
{
    my ($self) = @_;
    $dbh->selectcol_arrayref(qq~
        SELECT code FROM contest_problems WHERE contest_id = ? ORDER BY 1~, undef,
        $self->{id}
    );
}

sub unused_problem_codes
{
    my ($self) = @_;
    my %used_codes;
    @used_codes{@{$self->used_problem_codes}} = undef;
    grep !exists($used_codes{$_}), @cats::problem_codes;
}

1;
