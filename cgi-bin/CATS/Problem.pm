package CATS::Problem;

use lib '..';
use strict;
use warnings;
use Encode;

use CATS::Constants;
use CATS::Misc qw($dbh $uid new_id escape_html);
use CATS::BinaryFile;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use XML::Parser::Expat;
use CATS::DevEnv;

use fields qw(
    contest_id id import_log debug problem checker
    statement constraints input_format output_format
    tests samples objects keywords
    imports solutions generators modules pictures
    current_tests current_sample
    stml zip zip_archive old_title replace tag_stack has_checker de_list
);

sub new
{
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}


sub clear
{
    my CATS::Problem $self = shift;
    undef $self->{$_} for (keys %CATS::Problem::FIELDS);
    $self->{$_} = {} for qw(tests samples objects keywords);
    $self->{$_} = [] for qw(imports solutions generators modules pictures);
}


sub encoded_import_log
{
    my CATS::Problem $self = shift;
    return Encode::encode_utf8(escape_html($self->{import_log}));
}


sub load
{
    my CATS::Problem $self = shift;
    (my $fname, $self->{contest_id}, $self->{id}, $self->{replace}) = @_;

    eval 
    {
        CATS::BinaryFile::load($fname, \$self->{zip_archive})
            or $self->error("open '$fname' failed: $!");
                    
        $self->{zip} = Archive::Zip->new();
        $self->{zip}->read($fname) == AZ_OK
            or $self->error("read '$fname' failed -- probably not a zip archive");

        my @xml_members = $self->{zip}->membersMatching('.*\.xml');

        $self->error('*.xml not found') if !@xml_members;
        $self->error('found several *.xml in archive') if @xml_members > 1;

        $self->{tag_stack} = [];
        my $parser = new XML::Parser::Expat;
        $parser->setHandlers(
            Start => sub { $self->on_start_tag(@_) },
            End => sub { $self->on_end_tag(@_) },
            Char => sub { ${$self->{stml}} .= CATS::Misc::escape_xml($_[1]) if $self->{stml} },
        );
        $parser->parse($self->read_member($xml_members[0]));
    };

    if ($@)
    {
        $dbh->rollback unless $self->{debug};
        $self->note("Import failed: $@");
        return -1;
    }
    else
    {
        $dbh->commit unless $self->{debug};
        $self->note('Success');
        return 0;
    }
}


sub checker_added
{
    my CATS::Problem $self = shift;
    $self->{has_checker} and $self->error('Found several checkers');
    $self->{has_checker} = 1;
}


sub validate
{
    my CATS::Problem $self = shift;
    
    my $check_order = sub
    {
        my ($objects, $name) = @_;

        my @order = sort { $a <=> $b } keys %$objects;
        for (1..@order)
        {
            $order[$_ - 1] == $_ or $self->error("Missing $name #$_");
        }
    };

    $check_order->($self->{tests}, 'test');
    $check_order->($self->{samples}, 'sample');
}


sub required_attributes
{
    my CATS::Problem $self = shift;
    my ($el, $attrs, $names) = @_;
    for (@$names)
    {
        defined $attrs->{$_}
            or $self->error("$el.$_ not specified");
    }
}


sub set_named_object
{
    my CATS::Problem $self = shift;
    my ($name, $object) = @_;
    $name or return; 
    $self->error("Duplicate object reference: '$name'")
        if defined $self->{objects}->{$name};
    $self->{objects}->{$name} = $object;
}


sub get_named_object
{
    my CATS::Problem $self = shift;
    my ($name, $tag) = @_;
    defined $name or return undef;
    defined $self->{objects}->{$name}
        or $self->error("Undefined object reference: '$name' in '$tag'");
    return $self->{objects}->{$name};
}


sub check_top_tag
{
    (my CATS::Problem $self, my $allowed_tags) = @_;
    my $top_tag;
    $top_tag = @$_ ? $_->[$#$_] : '' for $self->{tag_stack};
    return grep $top_tag eq $_, @$allowed_tags;
}


sub comma_array { join ',', @{$_[0]} }


sub on_start_tag
{
    my CATS::Problem $self = shift;
    my ($p, $el, %atts) = @_;

    if ($self->{stml})
    {
        ${$self->{stml}} .=
            "<$el" . join ('', map qq~ $_="$atts{$_}"~, keys %atts) . '>';
        if ($el eq 'img')
        {
            $atts{picture} or $self->error('Picture not defined in img element');
            $self->get_named_object($atts{picture}, 'img')->{refcount}++;
        }
        return; 
    }

    my $h = tag_handlers()->{$el} or $self->error("Unknown tag $el");
    $self->error(
        sprintf 'Tag "%s" must be inside one of "%s" %s', $el, join(',', ${$h->{in}})
    ) if $h->{in} && !$self->check_top_tag($h->{in});
    $self->required_attributes($el, \%atts, $h->{r}) if $h->{r};
    $h->{s}->($self, \%atts, $el);
    push @{$self->{tag_stack}}, $el;
}


sub on_end_tag
{
    my CATS::Problem $self = shift;
    my ($p, $el, %atts) = @_;

    pop @{$self->{tag_stack}};

    my $h = tag_handlers()->{$el};
    $h->{e}->($self, \%atts, $el) if $h && $h->{e};
    if ($self->{stml})
    {
        ${$self->{stml}} .= "</$el>";
    }
    elsif (!$h)
    {
        $self->error("Unknown tag $el");
    }
}


sub stml_handlers {
    my $v = $_[0];
    ( s => sub { $_[0]->{stml} = \$_[0]->{$v} }, e => \&end_stml );
}


sub end_stml { undef $_[0]->{stml} }


sub tag_handlers()
{{
    CATS => { s => sub {}, r => ['version'] },
    ProblemStatement => { stml_handlers('statement') },
    ProblemConstraints => { stml_handlers('constraints') },
    InputFormat => { stml_handlers('input_format') },
    OutputFormat => { stml_handlers('output_format') },
    Problem => {
        s => \&start_tag_Problem, e => \&end_tag_Problem,
        r => ['title', 'lang', 'tlimit', 'inputFile', 'outputFile'], },
    Picture => { s => \&start_tag_Picture, r => ['src', 'name'] },
    Solution => { s => \&start_tag_Solution, r => ['src', 'name'] },
    Checker => { s => \&start_tag_Checker, r => ['src'] },
    Generator => { s => \&start_tag_Generator, r => ['src', 'name'] },
    GeneratorRange => {
        s => \&start_tag_Generator, r => ['src', 'name', 'from', 'to'] },
    Module => { s => \&start_tag_Module, r => ['src', 'de_code', 'type'] },
    Import => { s => \&start_tag_Import, r => ['guid'] },
    Test => {
        s => \&start_tag_Test, e => \&end_tag_Test, r => ['rank'] },
    TestRange => {
        s => \&start_tag_TestRange, e => \&end_tag_Test, r => ['from', 'to'] },
    In => { s => \&start_tag_In, in => ['Test', 'TestRange'] },
    Out => { s => \&start_tag_Out, in => ['Test', 'TestRange'] },
    Sample => { s => \&start_tag_Sample, e => \&end_tag_Sample, r => ['rank'] },
    SampleIn => { s => \&start_tag_SampleIn, e => \&end_stml, in => ['Sample'] },
    SampleOut => { s => \&start_tag_SampleOut, e => \&end_stml, in => ['Sample'] },
    Keyword => { s => \&start_tag_Keyword, r => ['code'] },
}}


sub start_tag_Problem
{
    (my CATS::Problem $self, my $atts) = @_;

    if (!defined $atts->{mlimit})
    {
        my $default_mlimit = 200;
        $self->warning("Problem.mlimit not specified. default: $default_mlimit");
        $atts->{mlimit} = $default_mlimit;
    }

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
        max_points => $atts->{maxPoints}
    };
    $self->checker_added if $self->{problem}->{std_checker};
    my $ot = $self->{old_title};
    $self->error("Problem was renamed unexpectedly, old title: $ot")
        if $ot && $self->{problem}->{title} ne $ot;
}


sub start_tag_Picture
{
    (my CATS::Problem $self, my $atts) = @_;

    $atts->{src} =~ /\.([^\.]+)$/ and my $ext = $1
        or $self->error("Invalid image extension for '$atts->{src}'");
        
    push @{$self->{pictures}},
        $self->set_named_object($atts->{name}, {
            id => new_id,
            $self->read_member_named(name => $atts->{src}, kind => 'picture'),
            name => $atts->{name}, ext => $ext, refcount => 0
        });
}


sub start_tag_Solution
{
    (my CATS::Problem $self, my $atts) = @_;

    my $sol = $self->set_named_object($atts->{name}, {
        id => new_id,
        $self->read_member_named(name => $atts->{src}, kind => 'solution'),
        de_code => $atts->{de_code},
        guid => $atts->{export}, checkup => $atts->{checkup},
    });
    push @{$self->{solutions}}, $sol;
}


sub start_tag_Checker
{
    (my CATS::Problem $self, my $atts) = @_;

    my $style = $atts->{style} || 'legacy';
    for ($style)
    {
        /^legacy$/ && do { $self->warning('Legacy checker found!'); last; };
        /^testlib$/ && last;
        $self->error(q~Unknown checker style (must be either 'legacy' or 'testlib')~);
    }

    $self->checker_added;
    $self->{checker} = {
        id => new_id,
        $self->read_member_named(name => $atts->{src}, kind => 'checker'),
        de_code => $atts->{de_code}, guid => $atts->{export}, style => $style
    };
}


sub create_generator
{
    (my CATS::Problem $self, my $p) = @_;
    
    return $self->set_named_object($p->{name}, {
        id => new_id,
        $self->read_member_named(name => $p->{src}, kind => 'generator'),
        de_code => $p->{de_code},
        outputFile => $p->{outputFile},
    });
}


sub start_tag_Generator
{
    (my CATS::Problem $self, my $atts) = @_;
    push @{$self->{generators}}, $self->create_generator($atts);
}


sub start_tag_GeneratorRange
{
    (my CATS::Problem $self, my $atts) = @_;
    for ($atts->{from} .. $atts->{to})
    {
        push @{$self->{generators}}, $self->create_generator({
            name => interpolate_rank($atts->{name}, $_),
            src => interpolate_rank($atts->{src}, $_),
            guid => interpolate_rank($atts->{export}, $_),
            de_code => $atts->{de_code},
            outputFile => $atts->{outputFile},
        });
    }
}


sub start_tag_Module
{
    (my CATS::Problem $self, my $atts) = @_;

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


sub start_tag_Import
{
    (my CATS::Problem $self, my $atts) = @_;

    my $guid = $atts->{guid};
    push @{$self->{imports}}, my $import = { guid => $guid };
    my ($src_id, $stype) = $self->{debug} ? (undef, undef) : $dbh->selectrow_array(qq~
        SELECT id, stype FROM problem_sources WHERE guid = ?~, undef, $guid);
    
    my $t = $atts->{type};
    !$t || ($t = $import->{type} = module_types()->{$t})
        or $self->error("Unknown import source type: $t");

    if ($src_id)
    {
        !$t || $stype == $t || $cats::source_modules{$stype} == $t
            or $self->error("Import type check failed for guid='$guid' ($t vs $stype)");
        $self->checker_added if $stype == $cats::checker || $stype == $cats::testlib_checker;
        $self->note("Imported source from guid='$guid'");
    }
    else
    {
        $self->warning("Import source not found for guid='$guid'");
    }
}


sub add_test
{
    (my CATS::Problem $self, my $atts, my $rank) = @_;
    !defined $self->{tests}->{$rank} or $self->error("Duplicate test $rank");
    push @{$self->{current_tests}},
        $self->{tests}->{$rank} = { rank => $rank, points => $atts->{points} };
}


sub start_tag_Test
{
    (my CATS::Problem $self, my $atts) = @_;

    my $r = $atts->{rank};
    $r =~ /^\d+$/ && $r > 0 && $r < 1000
        or $self->error("Bad rank: '$r'");
    $self->{current_tests} = [];
    $self->add_test($atts, $r);
}


sub start_tag_TestRange
{
    (my CATS::Problem $self, my $atts) = @_;
    $atts->{from} <= $atts->{to}
        or $self->error('TestRange.from > TestRange.to');
    $self->{current_tests} = [];
    $self->add_test($atts, $_) for ($atts->{from}..$atts->{to});
}


sub end_tag_Test
{
    my CATS::Problem $self = shift;
    undef $self->{current_tests};
}


sub start_tag_In
{
    (my CATS::Problem $self, my $atts) = @_;
    
    my @t = @{$self->{current_tests}};

    if (defined $atts->{src})
    {
        for (@t)
        {
            my $src = apply_test_rank($atts->{'src'}, $_->{rank});
            my $member = $self->{zip}->memberNamed($src)
                or $self->error("Invalid test input file reference: '$src'");
            $_->{in_file} = $self->{debug} ? $src : $self->read_member($member);
        }
    }
    elsif (defined $atts->{'use'})
    {
        for (@t)
        {
            my $use = apply_test_rank($atts->{'use'}, $_->{rank});
            $_->{generator_id} = $self->get_named_object($use, 'Test/In')->{id};
            $_->{param} = apply_test_rank($atts->{param}, $_->{rank});
        }
    }
    else
    {
        $self->error('Test input file not specified for tests ' . join (',', @t));
    }
}


sub start_tag_Out
{
    (my CATS::Problem $self, my $atts) = @_;

    my @t = @{$self->{current_tests}};

    if (defined $atts->{src})
    {
        for (@t)
        {
            my $src = apply_test_rank($atts->{'src'}, $_->{rank});
            my $member = $self->{zip}->memberNamed($src)
                or $self->error("Invalid test output file reference: '$src'");
            $_->{out_file} = $self->{debug} ? $src : $self->read_member($member);
        }
    }
    elsif (defined $atts->{'use'})
    {
        for (@t)
        {
            my $use = apply_test_rank($atts->{'use'}, $_->{rank});
            $_->{std_solution_id} = $self->get_named_object($use, 'Test/Out')->{id};
        }
    }
    else
    {
        $self->error('Test output file not specified for tests ' . join (',', @t));
    }
}


sub start_tag_Sample
{
    (my CATS::Problem $self, my $atts) = @_;
    
    my $r = $atts->{rank};
    $self->error("Duplicate sample $atts->{rank}")
        if defined $self->{samples}->{$r};

    $self->{current_sample} = $self->{samples}->{$r} =
        { sample_id => new_id, rank  => $r };
}


sub end_tag_Sample
{
    my CATS::Problem $self = shift;
    undef $self->{current_sample};
}


sub start_tag_SampleIn
{
    my CATS::Problem $self = shift;
    $self->{stml} = \$self->{current_sample}->{in_file};
}


sub start_tag_SampleOut
{
    my CATS::Problem $self = shift;
    $self->{stml} = \$self->{current_sample}->{out_file};
}


sub start_tag_Keyword
{
    (my CATS::Problem $self, my $atts) = @_;

    my $c = $atts->{code};
    !defined $self->{keywords}->{$c}
        or $self->warning("Duplicate keyword '$c'");
    $self->{keywords}->{$c} = 1;
}


sub module_types()
{{
    'checker' => $cats::checker_module,
    'solution' => $cats::solution_module,
    'generator' => $cats::generator_module,
}}


sub note($)
{
    my CATS::Problem $self = shift;
    $self->{import_log} .= "$_[0]\n";
}


sub warning($) 
{
    my CATS::Problem $self = shift;
    $self->{import_log} .= "Warning: $_[0]\n";
}


sub error($)
{
    my CATS::Problem $self = shift;
    $self->{import_log} .= "Error: $_[0]\n";
    die "Unrecoverable error";
}


sub read_member
{
    (my CATS::Problem $self, my $member) = @_;

    $member->desiredCompressionMethod(COMPRESSION_STORED);
    my $status = $member->rewindData();
    $status == AZ_OK or $self->error("code $status");

    my $data = '';
    while (!$member->readIsDone())
    {
        (my $buffer, $status) = $member->readChunk();
        $status == AZ_OK || $status == AZ_STREAM_END or $self->error("code $status");
        $data .= $$buffer;
    }
    $member->endRead();

    return $data;
}


sub read_member_named
{
    (my CATS::Problem $self, my %p) = @_;

    my $member = $self->{zip}->memberNamed($p{name}) 
        or $self->error("Invalid $p{kind} reference: '$p{name}'");

    return (src => ($self->{debug} ? $member : $self->read_member($member)), path => $p{name});
}


sub delete_child_records($)
{
    my ($pid) = @_;
    for (qw(pictures samples tests problem_sources problem_sources_import problem_keywords))
    {
        $dbh->do(qq~
            DELETE FROM $_ WHERE problem_id = ?~, undef, $pid);
    }
}


sub end_tag_Problem
{
    my CATS::Problem $self = shift;
    
    $self->validate;
    
    return if $self->{debug};
    
    if ($self->{replace})
    {
        delete_child_records($self->{id});
    }

    my $sql = $self->{replace}
    ? q~
        UPDATE problems 
        SET
            contest_id=?,
            title=?, lang=?, time_limit=?, memory_limit=?, difficulty=?, author=?, input_file=?, output_file=?, 
            statement=?, pconstraints=?, input_format=?, output_format=?, 
            zip_archive=?, upload_date=CATS_SYSDATE(), std_checker=?, last_modified_by=?,
            max_points=?, hash=NULL
        WHERE id = ?~
    : q~
        INSERT INTO problems (
            contest_id,
            title, lang, time_limit, memory_limit, difficulty, author, input_file, output_file,
            statement, pconstraints, input_format, output_format, zip_archive,
            upload_date, std_checker, last_modified_by, max_points, id
        ) VALUES (
            ?,?,?,?,?,?,?,?,?,?,?,?,?,?,CATS_SYSDATE(),?,?,?,?
        )~;
 
    my $c = $dbh->prepare($sql);
    my $i = 1;
    $c->bind_param($i++, $self->{contest_id});
    $c->bind_param($i++, $self->{problem}->{$_})
        for qw(title lang time_limit memory_limit difficulty author input_file output_file);
    $c->bind_param($i++, $self->{$_}, { ora_type => 113 })
        for qw(statement constraints input_format output_format zip_archive);
    $c->bind_param($i++, $self->{problem}->{std_checker});
    $c->bind_param($i++, $uid);
    $c->bind_param($i++, $self->{problem}->{max_points});
    $c->bind_param($i++, $self->{id});
    $c->execute;
    
    $self->insert_problem_content;
}                   
                    
                    
sub get_de_id
{
    my CATS::Problem $self = shift;
    my ($code, $path) = @_;
    
    $self->{de_list} ||= CATS::DevEnv->new($dbh);
    
    my $de;
    if (defined $code)
    {
        $de = $self->{de_list}->by_code($code)
            or $self->error("Unknown DE code: '$code' for source: '$path'");
    }
    else
    {
        $de = $self->{de_list}->by_file_extension($path)
            or $self->error("Can't detect de for source: '$path'");
        $self->note("Detected DE: '$de->{description}' for source: '$path'");
    }
    return $de->{id};
}


sub apply_test_rank
{
    my ($v, $rank) = @_;
    $v ||= '';
    $v =~ s/%n/$rank/g;
    $v =~ s/%0n/sprintf("%02d", $rank)/eg;
    $v =~ s/%%/%/g; 
    $v;
}


sub insert_problem_source
{
    my CATS::Problem $self = shift;
    my %p = @_;
    use Carp;
    my $s = $p{source_object} or confess;

    if ($s->{guid})
    {
        my $dup_id = $dbh->selectrow_array(qq~
            SELECT problem_id FROM problem_sources WHERE guid = ?~, undef, $s->{guid});
        $self->warning("Duplicate guid with problem $dup_id") if $dup_id;
    }
    my $c = $dbh->prepare(qq~
        INSERT INTO problem_sources (
            id, problem_id, de_id, src, fname, stype, input_file, output_file, guid
        ) VALUES (?,?,?,?,?,?,?,?,?)~);

    $c->bind_param(1, $s->{id});
    $c->bind_param(2, $self->{id});
    $c->bind_param(3, $self->get_de_id($s->{de_code}, $s->{path}));
    $c->bind_param(4, $s->{src}, { ora_type => 113 });
    $c->bind_param(5, $s->{path});
    $c->bind_param(6, $p{source_type});
    $c->bind_param(7, $s->{inputFile});
    $c->bind_param(8, $s->{outputFile});
    $c->bind_param(9, $s->{guid});
    $c->execute;

    my $g = $s->{guid} ? ", guid=$s->{guid}" : '';
    $self->note("$p{type_name} '$s->{path}' added$g");
}


sub insert_problem_content
{
    my CATS::Problem $self = shift;

    my $p = $self->{problem};

    $self->{has_checker} or $self->error('No checker specified');

    if ($p->{std_checker})
    {
        $self->note("Checker: $p->{std_checker}");
    }
    elsif (my $c = $self->{checker})
    {
        $self->insert_problem_source(
            source_object => $c, type_name => 'Checker',
            source_type => ($c->{style} eq 'legacy' ? $cats::checker : $cats::testlib_checker)
        );
    }

    for(@{$self->{generators}})
    {
        $self->insert_problem_source(
            source_object => $_, source_type => $cats::generator, type_name => 'Generator');
    }

    for(@{$self->{solutions}})
    {
        $self->insert_problem_source(
            source_object => $_, type_name => 'Solution',
            source_type => $_->{checkup} ? $cats::adv_solution : $cats::solution);
    }

    for (@{$self->{modules}})
    {
        $self->insert_problem_source(
            source_object => $_, source_type => $_->{type_code},
            type_name => "Module for $_->{type}");
    }

    for (@{$self->{imports}})
    {
        $dbh->do(q~
            INSERT INTO problem_sources_import (problem_id, guid) VALUES (?, ?)~, undef,
            $self->{id}, $_->{guid});
    }

    my $c = $dbh->prepare(qq~
        INSERT INTO pictures(id, problem_id, extension, name, pic)
            VALUES (?,?,?,?,?)~);
    for (@{$self->{pictures}})
    {

        $c->bind_param(1, $_->{id});     
        $c->bind_param(2, $self->{id});
        $c->bind_param(3, $_->{ext});
        $c->bind_param(4, $_->{name} );
        $c->bind_param(5, $_->{src}, { ora_type => 113 });
        $c->execute;

        $self->note("Picture '$_->{path}' added");
        $_->{refcount}
            or $self->warning("No references to picture '$_->{path}'");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO tests (
            problem_id, rank, generator_id, param, std_solution_id, in_file, out_file, points
        ) VALUES (?,?,?,?,?,?,?,?)~
    );

    for (sort { $a->{rank} <=> $b->{rank} } values %{$self->{tests}})
    {
        $c->bind_param(1, $self->{id});
        $c->bind_param(2, $_->{rank});
        $c->bind_param(3, $_->{generator_id});
        $c->bind_param(4, $_->{param});
        $c->bind_param(5, $_->{std_solution_id} );
        $c->bind_param(6, $_->{in_file}, { ora_type => 113 });
        $c->bind_param(7, $_->{out_file}, { ora_type => 113 });
        $c->bind_param(8, $_->{points});
        $c->execute
            or $self->error("Can not add test $_->{rank}: $dbh->errstr");
        $self->note("Test $_->{rank} added");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO samples (problem_id, rank, in_file, out_file)
        VALUES (?,?,?,?)~
    );
    for (values %{$self->{samples}})
    {
        $c->bind_param(1, $self->{id});
        $c->bind_param(2, $_->{rank});
        $c->bind_param(3, $_->{in_file}, { ora_type => 113 });
        $c->bind_param(4, $_->{out_file}, { ora_type => 113 });
        $c->execute;
        $self->note("Sample test $_->{rank} added");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO problem_keywords (problem_id, keyword_id) VALUES (?, ?)~);
    for (keys %{$self->{keywords}})
    {
        my ($keyword_id) = $dbh->selectrow_array(q~
            SELECT id FROM keywords WHERE code = ?~, undef, $_);
        if ($keyword_id)
        {
            $c->execute($self->{id}, $keyword_id);
            $self->note("Keyword added: $_");
        }
        else
        {
            $self->warning("Unknown keyword: $_");
        }
    }
}


1;

