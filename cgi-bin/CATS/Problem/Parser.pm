package CATS::Problem::Parser;

use strict;
use warnings;

use Encode;
use XML::Parser::Expat;
use JSON::XS;

use CATS::Utils qw(escape_xml);
use CATS::Constants;
use CATS::DB;
use FormalInput;

use CATS::Problem::Tests;

sub new
{
    my ($class, %opts) = @_;
    $opts{source} or die "Unknown source for parser";
    $opts{import_source} or die "Unknown import source";
    return bless \%opts => $class;
}

sub error
{
    my $self = shift;
    $self->{source}->error(@_);
}

sub note
{
    my $self = shift;
    $self->{source}->note(@_);
}

sub warning
{
    my $self = shift;
    $self->{source}->note(@_);
}

sub get_zip
{
    $_[0]->{source}->get_zip;
}

sub tag_handlers()
{{
    CATS => { s => sub {}, r => ['version'] },
    ProblemStatement => { stml_handlers('statement') },
    ProblemConstraints => { stml_handlers('constraints') },
    InputFormat => { stml_handlers('input_format') },
    OutputFormat => { stml_handlers('output_format') },
    FormalInput => { stml_handlers('formal_input'), e => \&end_tag_FormalInput },
    JsonData => { stml_handlers('json_data'), e => \&end_tag_JsonData },
    Explanation => { stml_handlers('explanation') },
    Problem => {
        s => \&start_tag_Problem, e => \&end_tag_Problem,
        r => ['title', 'lang', 'tlimit', 'inputFile', 'outputFile'], },
    Attachment => { s => \&start_tag_Attachment, r => ['src', 'name'] },
    Picture => { s => \&start_tag_Picture, r => ['src', 'name'] },
    Solution => { s => \&start_tag_Solution, r => ['src', 'name'] },
    Checker => { s => \&start_tag_Checker, r => ['src'] },
    Generator => { s => \&start_tag_Generator, r => ['src', 'name'] },
    Validator => { s => \&start_tag_Validator, r => ['src', 'name'] },
    GeneratorRange => {
        s => \&start_tag_GeneratorRange, r => ['src', 'name', 'from', 'to'] },
    Module => { s => \&start_tag_Module, r => ['src', 'de_code', 'type'] },
    Import => { s => \&start_tag_Import, r => ['guid'] },
    Test => { s => \&start_tag_Test, e => \&end_tag_Test, r => ['rank'] },
    TestRange => {
        s => \&start_tag_TestRange, e => \&end_tag_Test, r => ['from', 'to'] },
    In => { s => \&start_tag_In, in => ['Test', 'TestRange'] },
    Out => { s => \&start_tag_Out, in => ['Test', 'TestRange'] },
    Sample => { s => \&start_tag_Sample, e => \&end_tag_Sample, r => ['rank'] },
    SampleIn => { s => \&start_tag_SampleIn, e => \&end_stml, in => ['Sample'] },
    SampleOut => { s => \&start_tag_SampleOut, e => \&end_stml, in => ['Sample'] },
    Keyword => { s => \&start_tag_Keyword, r => ['code'] },
    Testset => { s => \&start_tag_Testset, r => ['name', 'tests'] },
    Run => { s => \&start_tag_Run, r => ['method'] },
}}

sub checker_type_names
{{
    legacy => $cats::checker,
    testlib => $cats::testlib_checker,
    partial => $cats::partial_checker,
}}

sub module_types()
{{
    'checker' => $cats::checker_module,
    'solution' => $cats::solution_module,
    'generator' => $cats::generator_module,
    'validator' => $cats::validator_module,
}}

sub required_attributes
{
    my ($self, $el, $attrs, $names) = @_;
    for (@$names) {
        defined $attrs->{$_}
            or $self->error("$el.$_ not specified");
    }
}

sub set_named_object
{
    my ($self, $name, $object) = @_;
    $name or return;
    $self->error("Duplicate object reference: '$name'")
        if defined $self->{objects}->{$name};
    $self->{objects}->{$name} = $object;
}

sub get_named_object
{
    my ($self, $name) = @_;
    defined $name or return undef;
    defined $self->{objects}->{$name}
        or $self->error(
            "Undefined object reference: '$name' in " . join '/', @{$self->{tag_stack}}
        );
    return $self->{objects}->{$name};
}

sub get_imported_id
{
    my ($self, $name) = @_;
    for (@{$self->{imports}}) {
        return $_->{src_id} if $name eq ($_->{name} || '');
    }
    undef;
}

sub read_member_named
{
    my ($self, %p) = @_;

    return (
        src => $self->{source}->read_member($p{name}, "Invalid $p{kind} reference: '$p{name}'"),
        path => $p{name}
    );
}

sub check_top_tag
{
    my ($self, $allowed_tags) = @_;
    my $top_tag;
    $top_tag = @$_ ? $_->[$#$_] : '' for $self->{tag_stack};
    return grep $top_tag eq $_, @$allowed_tags;
}

sub checker_added
{
    my $self = shift;
    $self->{has_checker} and $self->error('Found several checkers');
    $self->{has_checker} = 1;
}

sub create_generator
{
    my ($self, $p) = @_;

    return $self->set_named_object($p->{name}, {
        $self->problem_source_common_params($p, 'generator'),
        outputFile => $p->{outputFile},
    });
}

sub create_validator
{
    my ($self, $p) = @_;
    return $self->set_named_object($p->{name}, {
        $self->problem_source_common_params($p, 'validator')
    });
}

sub validate
{
    my $self = shift;

    my $check_order = sub {
        my ($objects, $name) = @_;
        for (1 .. keys %$objects) {
            exists $objects->{$_} or $self->error("Missing $name #$_");
        }
    };

    $self->apply_test_defaults;
    $check_order->($self->{tests}, 'test');
    my @t = values %{$self->{tests}};
    for (sort {$a->{rank} <=> $b->{rank}} @t) {
        my $error = validate_test($_) or next;
        $self->error("$error for test $_->{rank}");
    }
    my @without_points = map $_->{rank}, grep !defined $_->{points}, @t;
    $self->warning('Points not defined for tests: ' . join ',', @without_points)
        if @without_points && @without_points != @t;

    $check_order->($self->{samples}, 'sample');

    $self->{run_method} ||= $cats::rm_default;

    # insert_problem_content
    $self->{has_checker} or $self->error('No checker specified');
}

sub on_start_tag
{
    my ($self, $p, $el, %atts) = @_;

    if ($self->{stml}) {
        if ($el eq 'include') {
            my $name = $atts{src} or
                return $self->error(q~Missing required 'src' attribute of 'include' tag~);
            ${$self->{stml}} .= Encode::decode($self->{encoding}, $self->{source}->read_member($name, "Invalid 'include' reference: '$name'"));
            return;
        }
        ${$self->{stml}} .=
            "<$el" . join ('', map qq~ $_="$atts{$_}"~, keys %atts) . '>';
        if ($el eq 'img') {
            $atts{picture} or $self->error('Picture not defined in img element');
            $self->get_named_object($atts{picture})->{refcount}++;
        }
        elsif ($el =~ /^a|object$/) {
            $self->get_named_object($atts{attachment})->{refcount}++ if $atts{attachment};
        }
        return;
    }

    my $h = tag_handlers()->{$el} or $self->error("Unknown tag $el");
    if (my $in = $h->{in}) {
        $self->check_top_tag($in)
            or $self->error("Tag '$el' must be inside of " . join(' or ', @$in));
    }
    $self->required_attributes($el, \%atts, $h->{r}) if $h->{r};
    push @{$self->{tag_stack}}, $el;
    $h->{s}->($self, \%atts, $el);
}

sub on_end_tag
{
    my ($self, $p, $el, %atts) = @_;

    my $h = tag_handlers()->{$el};
    $h->{e}->($self, \%atts, $el) if $h && $h->{e};
    pop @{$self->{tag_stack}};

    if ($self->{stml}) {
        return if $el eq 'include';
        ${$self->{stml}} .= "</$el>";
    }
    elsif (!$h) {
        $self->error("Unknown tag $el");
    }
}

sub stml_handlers
{
    my $v = $_[0];
    ( s => sub { $_[0]->{stml} = \$_[0]->{$v} }, e => \&end_stml );
}

sub end_stml
{
    undef $_[0]->{stml}
}

sub end_tag_FormalInput
{
    my ($self, $atts) = @_;
    my $parser_err = FormalInput::parserValidate(${$self->{stml}});
    if ($parser_err) {
        my $s = FormalInput::errorMessageByCode(FormalInput::getErrCode($parser_err));
        my $l = FormalInput::getErrLine($parser_err);
        my $p = FormalInput::getErrPos($parser_err);
        $self->error("FormalInput: $s. Line: $l. Pos: $p.");
    } else {
        $self->note('FormalInput OK.');
    }
    $self->end_stml;
}

sub end_tag_JsonData
{
    my ($self, $atts) = @_;
    ${$self->{stml}} = Encode::encode_utf8(${$self->{stml}});
    eval { decode_json(${$self->{stml}}) };
    if ($@) {
        $self->error("JsonData: $@");
    } else {
        $self->note('JsonData OK.');
    }
    $self->end_stml;
}

sub start_tag_Problem
{
    my ($self, $atts) = @_;

    $self->{problem} = {
        title => $atts->{title},
        lang => $atts->{lang},
        time_limit => $atts->{tlimit},
        memory_limit => $atts->{mlimit},
        difficulty => $atts->{difficulty},
        author => $atts->{author},
        input_file => $atts->{inputFile},
        output_file => $atts->{outputFile},
        std_checker => $atts->{stdChecker},
        max_points => $atts->{maxPoints},
    };
    for ($self->{problem}->{memory_limit}) {
        last if defined $_;
        $_ = 200;
        $self->warning("Problem.mlimit not specified. default: $_");
    }

    if ($self->{problem}->{std_checker}) {
        $self->warning("Deprecated attribute 'stdChecker', use Import instead");
        $self->checker_added;
    }

    # TODO set old title
    my $ot = $self->{old_title};
    $self->error(sprintf
        "Unexpected problem rename from: $ot to: $self->{problem}->{title}",
    ) if $ot && $self->{problem}->{title} ne $ot;
}

sub end_tag_Problem
{
    $_[0]->validate;
}

sub start_tag_Attachment
{
    my ($self, $atts) = @_;

    push @{$self->{attachments}},
        $self->set_named_object($atts->{name}, {
            id => new_id,
            $self->read_member_named(name => $atts->{src}, kind => 'attachment'),
            name => $atts->{name}, file_name => $atts->{src}, refcount => 0
        });
}

sub start_tag_Picture
{
    my ($self, $atts) = @_;

    $atts->{src} =~ /\.([^\.]+)$/ and my $ext = $1
        or $self->error("Invalid image extension for '$atts->{src}'");

    push @{$self->{pictures}},
        $self->set_named_object($atts->{name}, {
            id => new_id,
            $self->read_member_named(name => $atts->{src}, kind => 'picture'),
            name => $atts->{name}, ext => $ext, refcount => 0
        });
}

sub problem_source_common_params
{
    my ($self, $atts, $kind) = @_;
    return (
        id => new_id,
        $self->read_member_named(name => $atts->{src}, kind => $kind),
        de_code => $atts->{de_code},
        guid => $atts->{export},
        time_limit => $atts->{timeLimit},
        memory_limit => $atts->{memoryLimit},
    );
}

sub start_tag_Solution
{
    my ($self, $atts) = @_;

    my $sol = $self->set_named_object($atts->{name}, {
        $self->problem_source_common_params($atts, 'solution'),
        checkup => $atts->{checkup},
    });
    push @{$self->{solutions}}, $sol;
}

sub start_tag_Checker
{
    my ($self, $atts) = @_;

    my $style = $atts->{style} || 'legacy';
    checker_type_names->{$style}
        or $self->error(q~Unknown checker style (must be 'legacy', 'testlib' or 'partial')~);
    $style ne 'legacy'
        or $self->warning('Legacy checker found!');
    $self->checker_added;
    $self->{checker} = {
        $self->problem_source_common_params($atts, 'checker'), style => $style
    };
}

sub start_tag_Generator
{
    my ($self, $atts) = @_;
    push @{$self->{generators}}, $self->create_generator($atts);
}

sub start_tag_Validator
{
    my ($self, $atts) = @_;
    push @{$self->{validators}}, $self->create_validator($atts);
}

sub start_tag_GeneratorRange
{
    my ($self, $atts) = @_;
    for ($atts->{from} .. $atts->{to}) {
        push @{$self->{generators}}, $self->create_generator({
            name => apply_test_rank($atts->{name}, $_),
            src => apply_test_rank($atts->{src}, $_),
            export => apply_test_rank($atts->{export}, $_),
            de_code => $atts->{de_code},
            outputFile => $atts->{outputFile},
        });
    }
}

sub start_tag_Module
{
    my ($self, $atts) = @_;

    exists module_types()->{$atts->{type}}
        or $self->error("Unknown module type: '$atts->{type}'");
    push @{$self->{modules}}, {
        id => new_id,
        $self->read_member_named(name => $atts->{src}, kind => 'module'),
        de_code => $atts->{de_code},
        guid => $atts->{export}, type => $atts->{type},
        type_code => module_types()->{$atts->{type}},
    };
}

sub import_one_source
{
    my ($self, $guid, $name, $type) = @_;
    push @{$self->{imports}}, my $import = { guid => $guid, name => $name };
    my ($src_id, $stype) = $self->{debug} ? (undef, undef) : $self->{import_source}->get_sources($guid);

    !$type || ($type = $import->{type} = module_types()->{$type})
        or $self->error("Unknown import source type: $type");

    if ($src_id) {
        !$type || $stype == $type || $cats::source_modules{$stype} == $type
            or $self->error("Import type check failed for guid='$guid' ($type vs $stype)");
        $self->checker_added if $cats::source_modules{$stype} == $cats::checker_module;
        $import->{src_id} = $src_id;
        $self->note("Imported source from guid='$guid'");
    } else {
        $self->warning("Import source not found for guid='$guid'");
    }

}

sub start_tag_Import
{
    my ($self, $atts) = @_;
    my ($guid, @nt) = @$atts{qw(guid name type)};
    if ($guid =~ /\*/) {
        $guid =~ s/%/\\%/g;
        $guid =~ s/\*/%/g;
        $self->import_one_source($_, @nt) for $self->{import_source}->get_guids($guid);
    } else {
        $self->import_one_source($guid, @nt);
    }
}

sub start_tag_Sample
{
    my ($self, $atts) = @_;

    my $r = $atts->{rank};
    $self->error("Duplicate sample $r") if defined $self->{samples}->{$r};

    $self->{current_sample} = $self->{samples}->{$r} = {
        sample_id => new_id,
        rank => $r
    };
}

sub end_tag_Sample
{
    my $self = shift;
    undef $self->{current_sample};
}

sub sample_in_out
{
    my ($self, $atts, $in_out) = @_;
    if (my $src = $atts->{src}) {
        $self->{current_sample}->{$in_out} = $self->{source}->read_member($src, "Invalid sample $in_out reference: '$src'");
    } else {
        $self->{stml} = \$self->{current_sample}->{$in_out};
    }
}

sub start_tag_SampleIn
{
    $_[0]->sample_in_out($_[1], 'in_file');
}

sub start_tag_SampleOut
{
    $_[0]->sample_in_out($_[1], 'out_file');
}

sub start_tag_Keyword
{
    my ($self, $atts) = @_;

    my $c = $atts->{code};
    !defined $self->{keywords}->{$c}
        or $self->warning("Duplicate keyword '$c'");
    $self->{keywords}->{$c} = 1;
}

sub start_tag_Testset
{
    my ($self, $atts) = @_;
    my $n = $atts->{name};
    $self->{testsets}->{$n} and $self->error("Duplicate testset '$n'");
    $self->parse_test_rank($atts->{tests});
    $self->{testsets}->{$n} = {
        id => new_id,
        map { $_ => $atts->{$_} } qw(name tests points comment hideDetails)
    };
    $self->{testsets}->{$n}->{hideDetails} ||= 0;
    $self->note("Testset $n added");
}

sub start_tag_Run
{
    my ($self, $atts) = @_;
    my $m = $atts->{method};
    $self->error("Duplicate run method '$m'") if defined $self->{run_method};
    my %methods = (
        default => $cats::rm_default,
        interactive => $cats::rm_interactive,
    );
    defined($self->{run_method} = $methods{$m})
        or $self->error("Unknown run method: '$m', must be one of: " . join ', ', keys %methods);
    $self->note("Run method set to '$m'");
}

sub parse_xml
{
    my ($self, $xml_file) = @_;
    $self->{tag_stack} = [];

    my $parser = new XML::Parser::Expat;
    $parser->setHandlers(
        Start => sub { $self->on_start_tag(@_) },
        End => sub { $self->on_end_tag(@_) },
        Char => sub { ${$self->{stml}} .= escape_xml($_[1]) if $self->{stml} },
        XMLDecl => sub { $self->{encoding} = $_[2] },
    );
    my $data = $self->{source}->read_member($xml_file);
    $parser->parse($self->{source}->read_member($xml_file));
}

sub parse
{
    my $self = shift;
    eval {
        $self->{source}->init;

        my @xml_members = $self->{source}->find_members('.*\.xml$');
        $self->error('*.xml not found') if !@xml_members;
        $self->error('found several *.xml in archive') if @xml_members > 1;

        $self->parse_xml($xml_members[0]);
    };
    return $@ ? -1 : 0;
}


1;
