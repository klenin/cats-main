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

my %problem_key_to_tag = (allow_des => 'AllowDEs', map { $_ => _snake_to_camel_case($_) } qw(
    tags code color status testsets contest_id problem_id max_points remote_url
    time_limit write_limit memory_limit process_limit points_testsets repo_path
));

my %key_to_tag = (ctype => 'ContestType', map { $_ => _snake_to_camel_case($_) } qw(
    id rules title closed penalty max_reqs is_hidden local_only show_sites show_flags
    start_date short_descr is_official finish_date run_all_tests req_selection show_packages show_explanations
    show_all_tests freeze_date defreeze_date show_test_data max_reqs_except show_frozen_reqs show_all_results
    pinned_judges_only show_test_resources show_checker_comment penalty_except
    pub_reqs_date show_all_for_solved apikey login_prefix offset_start_until
));

my %tag_to_key = (Problem => '', reverse(( %key_to_tag, %problem_key_to_tag )));

my %enums = (
    ctype => [ qw(normal training) ],
    rules => [ qw(icpc school) ],
    req_selection => [ qw(last best) ],
    status => [ qw(manual ready compile suspended disabled hidden) ],
);

sub maybe_enum { exists $enums{$_[0]} ? $enums{$_[0]}->[$_[1]] : $_[1] }

# [ tag, content ]

sub struct_to_string {
    my ($struct, $depth) = @_;
    $depth //= '';
    my ($tag, $content) = @$struct;
    my $content_str = ref $content ?
        join("\n", '', (map struct_to_string($_, "  $depth"), @$content), '') . $depth :
        $content;
    "$depth<$tag>$content_str</$tag>"
}

sub _serialize {
    my ($self, $entity, $tags) = @_;
    map [ $tags->{$_}, maybe_enum($_, $entity->{$_}) ],
    grep defined $entity->{$_} && exists $tags->{$_},
    sort keys %$entity;
}

sub _serialize_problem {
    my ($self, $problem) = @_;
    [ 'Problem', [ $self->_serialize($problem, \%problem_key_to_tag) ] ];
}

sub serialize_problem { struct_to_string(_serialize_problem(@_)) }

sub serialize {
    my ($self, $contest, $problems) = @_;
    qq~<?xml version="1.0"?>\n~ .
    struct_to_string([ 'CATS-Contest', [
        $self->_serialize($contest, \%key_to_tag),
        (map [ 'ContestTag', $_->{name} ], @{$contest->{tags} // []}),
        (map $self->_serialize_problem($_), @$problems)
    ]]);
}

sub error {
    my ($self, $msg) = @_;
    $self->{logger}->error(sprintf
        "%s at line %d col %d",
        $msg, $self->{parser}->current_line, $self->{parser}->current_column,
    ) if $self->{logger};
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
    $value + 0;
}

sub to_bool {
    (my CATS::Contest::XmlSerializer $self, my $el) = @_;
    my $value = $self->{tag_stack}->[-1]->{text};
    $value =~ s/^\s*(0|1)\s*$/$1/ or $self->error("Value of $el is not bool");
    $value + 0;
}

sub to_string {
    (my CATS::Contest::XmlSerializer $self, my $el) = @_;
    $self->{tag_stack}->[-1]->{text} || '';
}

sub to_enum {
    (my CATS::Contest::XmlSerializer $self, my $el) = @_;
    my $value = to_string($self, $el);
    my $key = $tag_to_key{$el};
    my $values = $enums{$key};
    my $index = first { $values->[$_] eq $value } 0..$#$values;
    $self->error("Value of $el must be one of: " . join ', ', @$values) if !defined $index;
    $index;
}

sub to_date {
    to_string(@_);
}

sub to_array {
    (my CATS::Contest::XmlSerializer $self, my $el) = @_;
    [ map /(\d+)/ ? $1 : (), split /,/, to_string($self, $el) ]
}

sub assign_contest_prop {
    (my CATS::Contest::XmlSerializer $self, my $el, my $fn) = @_;
    my $key = $tag_to_key{$el};
    $self->{contest}->{$key} = $fn->($self, $el);
}

sub assign_contest_tag {
    (my CATS::Contest::XmlSerializer $self, my $el, my $fn) = @_;
    push @{ $self->{contest}->{tags} //= [] }, $fn->($self, $el);
}

sub assign_problem_prop {
    (my CATS::Contest::XmlSerializer $self, my $el, my $fn) = @_;
    my $key = $tag_to_key{$el};
    $self->{problems}->[-1]->{$key} = $fn->($self, $el);
}

# s - start, e - end, r - required attrs, in - allowed to be in tags
sub tag_handlers() {{
    # contest
    'CATS-Contest' => { in => [] },
    Id => { e => sub { assign_contest_prop(@_, \&to_int) } },
    Rules => { e => sub { assign_contest_prop(@_, \&to_enum) } },
    Title => { e => sub { assign_contest_prop(@_, \&to_string) } },
    Closed => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    Penalty => { e => sub { assign_contest_prop(@_, \&to_int) } },
    MaxReqs => { e => sub { assign_contest_prop(@_, \&to_int) } },
    IsHidden => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    LocalOnly => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    ShowSites => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    ShowFlags => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    StartDate => { e => sub { assign_contest_prop(@_, \&to_date) } },
    ShortDescr => { e => sub { assign_contest_prop(@_, \&to_string) } },
    IsOfficial => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    FinishDate => { e => sub { assign_contest_prop(@_, \&to_date) } },
    PubReqsDate => { e => sub { assign_contest_prop(@_, \&to_date) } },
    OffsetStartUntil => { e => sub { assign_contest_prop(@_, \&to_date) } },
    RunAllTests => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    ContestType => { e => sub { assign_contest_prop(@_, \&to_enum) } },
    ReqSelection => { e => sub { assign_contest_prop(@_, \&to_enum) } },
    ShowPackages => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    ShowAllTests => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    FreezeDate => { e => sub { assign_contest_prop(@_, \&to_date) } },
    DefreezeDate => { e => sub { assign_contest_prop(@_, \&to_date) } },
    ShowTestData => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    MaxReqsExcept => { e => sub { assign_contest_prop(@_, \&to_string) } },
    ShowFrozenReqs => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    ShowAllResults => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    PinnedJudgesOnly => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    ShowTestResources => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    ShowCheckerComment => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    ShowAllForSolved => { e => sub { assign_contest_prop(@_, \&to_bool) } },
    ContestTag => { e => sub { assign_contest_tag(@_, \&to_string) } },
    Apikey => { e => sub { assign_contest_prop(@_, \&to_string) } },
    LoginPrefix => { e => sub { assign_contest_prop(@_, \&to_string) } },
    # problem
    Code => { e => sub { assign_problem_prop(@_, \&to_string) }, in => [ 'Problem' ] },
    Tags => { e => sub { assign_problem_prop(@_, \&to_string) }, in => [ 'Problem' ] },
    Color => { e => sub { assign_problem_prop(@_, \&to_string) }, in => [ 'Problem' ] },
    Status => { e => sub { assign_problem_prop(@_, \&to_enum) }, in => [ 'Problem' ] },
    Problem => { s => sub { push @{$_[0]->{problems}}, { } } },
    AllowDEs => { e => sub { assign_problem_prop(@_, \&to_array) }, in => [ 'Problem' ] },
    Testsets => { e => sub { assign_problem_prop(@_, \&to_string) }, in => [ 'Problem' ] },
    RepoPath => { e => sub { assign_problem_prop(@_, \&to_string) }, in => [ 'Problem' ] },
    RemoteUrl => { e => sub { assign_problem_prop(@_, \&to_string) }, in => [ 'Problem' ] },
    MaxPoints => { e => sub { assign_problem_prop(@_, \&to_int) }, in => [ 'Problem' ] },
    ContestId => { e => sub { assign_problem_prop(@_, \&to_int) }, in => [ 'Problem' ] },
    TimeLimit => { e => sub { assign_problem_prop(@_, \&to_int) }, in => [ 'Problem' ] },
    ProblemId => { e => sub { assign_problem_prop(@_, \&to_int) }, in => [ 'Problem' ] },
    WriteLimit => { e => sub { assign_problem_prop(@_, \&to_int) }, in => [ 'Problem' ] },
    MemoryLimit => { e => sub { assign_problem_prop(@_, \&to_int) }, in => [ 'Problem' ] },
    ProcessLimit => { e => sub { assign_problem_prop(@_, \&to_int) }, in => [ 'Problem' ] },
    PointsTestsets => { e => sub { assign_problem_prop(@_, \&to_string) }, in => [ 'Problem' ] },
}}

sub check_top_tag {
    (my CATS::Contest::XmlSerializer $self, my $allowed_tags) = @_;
    my $top_tag;
    $top_tag = @$_ ? $_->[$#$_]->{tag} : '' for $self->{tag_stack};
    grep $top_tag eq $_, @$allowed_tags;
}

sub on_start_tag {
    (my CATS::Contest::XmlSerializer $self, my $p, my $el, my %attrs) = @_;

    my $h = tag_handlers()->{$el};
    $h or $self->error("Unknown tag $el");

    my $in = $h->{in} // [ 'CATS-Contest' ];
    !@$in || $self->check_top_tag($in) or $self->error("$el must be inside " . join ' or ', @$in);

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
    $self->{problems} = [];

    $self->{parser} = XML::Parser::Expat->new;

    $self->{parser}->setHandlers(
        Start => sub { $self->on_start_tag(@_) },
        End => sub { $self->on_end_tag(@_) },
        Char => sub { $self->on_char(@_) },
    );

    $self->{parser}->parse($xml);
    $self->{contest}->{problems} = $self->{problems};
    $self->{contest};
}

1;
