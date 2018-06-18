package CATS::Contest::XmlSerializer;

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;
    bless \%opts => $class;
}

sub _snake_to_camel_case {
    my ($key) = @_;
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
    status => [ qw(manual ready compile suspended disabled hidden) ],
);

sub maybe_enum { exists $enums{$_[0]} ? $enums{$_[0]}->[$_[1]] : $_[1] }

sub enclose_in_tag { "<$_[0]>$_[1]</$_[0]>" }

sub _serialize {
    my ($self, $entity, $tags) = @_;
    map enclose_in_tag($tags->{$_}, maybe_enum($_, $entity->{$_})),
    grep defined $entity->{$_} && exists $tags->{$_},
    sort keys %$entity;
}

sub serialize_problem {
    my ($self, $problem) = @_;
    join "\n", '<Problem>', $self->_serialize($problem, \%problem_key_to_tag), '<Problem>';
}

sub serialize {
    my ($self, $contest, $problems) = @_;
    join "\n",
        q~<?xml version="1.0"?>~,
        '<CATS-Contest>',
        $self->_serialize($contest, \%key_to_tag),
        (map $self->serialize_problem($_), @$problems),
        '</CATS-Contest>';
}
