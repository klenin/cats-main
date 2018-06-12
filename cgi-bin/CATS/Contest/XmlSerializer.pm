package CATS::Contest::XmlSerializer;

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;
    bless \%opts => $class;
}

sub _snake_to_camel_case {
    my $key = shift; 
    $key =~ s/(_|^)(\w)/\U$2/g;
    $key;
}

my %problem_key_to_tag = (map { $_ => _snake_to_camel_case($_) } qw(
    id tags code color status testsets contest_id problem_id max_points 
    time_limit write_limit memory_limit process_limit points_testsets
));

my %key_to_tag = ( ctype => 'ContestType', map { $_ => _snake_to_camel_case($_) } qw(
    id rules title closed penalty max_reqs is_hidden local_only show_sites show_flags
    start_date short_descr is_official finish_date run_all_tests req_selection show_packages
    show_all_tests defreeze_date show_test_data max_reqs_except show_frozen_reqs show_all_results 
    pinned_judge_only show_test_resources show_checker_comment
));

my %enums = (
    ctype => [ qw(normal training) ],
    rules => [ qw(ACM school) ],
    req_selection => [ qw(last best) ],
    status => [ qw(manual ready compile suspended disabled hidden) ]
);

sub is_enum { exists $enums{$_[0]} }

sub enclose_in_tag {
    my ($key, $tag_set, $value) = @_;
    my $tag_name = $tag_set->{$key};
    return '' if !defined $tag_name;
    "<$tag_name>$value</$tag_name>\n";
}

sub _serialize {
    my ($self, $entity, $tag_set) = @_;
    my $xml = '';
    for my $key (sort keys %{$entity}) {
        next if !defined $entity->{$key};
        $xml .= enclose_in_tag $key, $tag_set, is_enum($key) ?
            $enums{$key}->[$entity->{$key}] : $entity->{$key};
    }
    $xml;
}

sub serialize_problem {
    my ($self, $problem) = @_;
    "<Problem>\n" .
    $self->_serialize($problem, \%problem_key_to_tag) .
    "<Problem>\n";
}

sub serialize {
    my ($self, $contest, $problems) = @_;
    my $xml = "<?xml version=\"1.0\"?>\n<CATS-Contest>\n" .
    $self->_serialize($contest, \%key_to_tag);
    $xml .= $self->serialize_problem($_) for @{$problems}; 
    $xml . "</CATS-Contest>\n";
}
