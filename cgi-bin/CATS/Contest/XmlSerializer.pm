package CATS::Contest::XmlSerializer;

use strict;
use warnings;

use List::Util qw(first);
use XML::Parser::Expat;

use CATS::Utils qw(escape_xml);

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

my %tag_to_key = reverse %key_to_tag;

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
    join "\n", '<Problem>', $self->_serialize($problem, \%problem_key_to_tag), '</Problem>';
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

sub error {
    my ($self, $msg) = @_;
    $self->{logger}->error($msg) if $self->{logger};
}

sub note {
    my ($self, $msg) = @_;
    $self->{logger}->note($msg) if $self->{logger};
}

sub warning {
    my ($self, $msg) = @_;
    $self->{logger}->warning($msg) if $self->{logger};
}

sub to_int {
    (my CATS::Contest::XmlSerializer $self, my $el) = @_;
    my $value = $self->{tag_stack}->[-1]->{text};
    $value =~ s/^\s*(\d+)\s*$/$1/ or $self->error("Value of $el is not int");
    $self->{contest}->{$tag_to_key{$el}} = $value + 0;
}

sub to_bool {
    (my CATS::Contest::XmlSerializer $self, my $el) = @_;
    my $value = $self->{tag_stack}->[-1]->{text};
    $value =~ s/^\s*(0|1)\s*$/$1/ or $self->error("Value of $el is not bool");
    $self->{contest}->{$tag_to_key{$el}} = $value + 0;
}

sub to_string {
    (my CATS::Contest::XmlSerializer $self, my $el) = @_;
    $self->{contest}->{$tag_to_key{$el}} = $self->{tag_stack}->[-1]->{text} || '';
}

sub to_enum {
    (my CATS::Contest::XmlSerializer $self, my $el) = @_;
    my $value = to_string($self, $el);
    my $key = $tag_to_key{$el};
    my $values = $enums{$key};
    my $index = first { $values->[$_] eq $value } 0..$#$values;
    $self->error("Value of $el is not enum") if !defined $index;
    $self->{contest}->{$key} = $index;
}

sub to_date {
    to_string(@_);
}

# s - start, e - end, r - required attrs, in - allowed to be in tags
sub tag_handlers() {{
    'CATS-Contest' => { in => [] },
    Id => { e => \&to_int },
    Rules => { e => \&to_enum },
    Title => { e => \&to_string },
    Closed => { e => \&to_bool },
    Penalty => { e => \&to_int },
    MaxReqs => { e => \&to_int },
    IsHidden => { e => \&to_bool },
    LocalOnly => { e => \&to_bool },
    ShowSites => { e => \&to_bool },
    ShowFlags => { e => \&to_bool },
    StartDate => { e => \&to_date },
    ShortDescr => { e => \&to_string },
    IsOfficial => { e => \&to_bool },
    FinishDate => { e => \&to_date },
    RunAllTests => { e => \&to_bool },
    ContestType => { e => \&to_enum },
    ReqSelection => { e => \&to_enum },
    ShowPackages => { e => \&to_bool },
    ShowAllTests => { e => \&to_bool },
    DefreezeDate => { e => \&to_date },
    ShowTestData => { e => \&to_bool },
    MaxReqsExcept => { e => \&to_string },
    ShowFrozenReqs => { e => \&to_bool },
    ShowAllResults => { e => \&to_bool },
    PinnedJudgeOnly => { e => \&to_bool },
    ShowTestResources => { e => \&to_bool },
    ShowCheckerComment => { e => \&to_bool },
}}

sub check_top_tag {
    (my CATS::Contest::XmlSerializer $self, my $allowed_tags) = @_;
    my $top_tag;
    $top_tag = @$_ ? $_->[$#$_]->{tag} : '' for $self->{tag_stack};
    grep $top_tag eq $_, @$allowed_tags;
}

sub check_required_attrs {
    my CATS::Contest::XmlSerializer $self = shift;
    my ($el, $attrs, $names) = @_;
    for (@$names) {
        defined $attrs->{$_}
            or $self->error("$el.$_ not specified");
    }
}

sub on_start_tag {
    (my CATS::Contest::XmlSerializer $self, my $p, my $el, my %attrs) = @_;

    my $h = tag_handlers()->{$el};
    $h or $self->error("Unknown tag $el");

    my $in = $h->{in} // [ 'CATS-Contest' ];
    !@$in || $self->check_top_tag($in) or $self->error("$el must be inside " . join ' or ', @$in);
    $self->check_required_attrs($el, \%attrs, $h->{r});

    push @{$self->{tag_stack}}, { tag => $el };
    $h->{s}->($self, \%attrs, $el) if defined $h->{s};
}

sub on_end_tag {
    (my CATS::Contest::XmlSerializer $self, my $p, my $el) = @_;
    my $h = tag_handlers()->{$el} or $self->error("Unknown tag $el");
    $h->{e}->($self, $el) if defined $h->{e};
    $el eq pop(@{$self->{tag_stack}})->{tag} or $self->error("Mismatched closing tag $el");
}

sub on_char {
    (my CATS::Contest::XmlSerializer $self, my $p, my $data) = @_;
    my $tag = $self->{tag_stack}->[-1];
    $tag->{text} = $tag->{text} ?
        ($tag->{text} . escape_xml($data)) : escape_xml($data);
}

sub parse_xml {
    my ($self, $xml) = @_;

    $self->{tag_stack} = [];
    $self->{contest} = {};

    my $xml_parser = XML::Parser::Expat->new;

    $xml_parser->setHandlers(
        Start => sub { $self->on_start_tag(@_) },
        End => sub { $self->on_end_tag(@_) },
        Char => sub { $self->on_char(@_) },
    );

    $xml_parser->parse($xml);
    $self->{contest};
}

1;
