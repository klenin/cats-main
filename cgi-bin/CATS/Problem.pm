package CATS::Problem;

use lib '..';
use strict;
use warnings;

use Encode;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use XML::Parser::Expat;
use JSON::XS;

use CATS::Constants;
use CATS::DB;
use CATS::Misc qw($git_author_name $git_author_email cats_dir msg);
use CATS::Utils qw(escape_html);
use CATS::BinaryFile;
use CATS::StaticPages;
use CATS::DevEnv;
use FormalInput;

use fields qw(
    contest_id id import_log debug problem checker
    statement constraints input_format output_format formal_input json_data explanation
    tests testsets samples objects keywords
    imports solutions generators modules pictures attachments
    test_defaults current_tests current_sample gen_groups
    encoding stml zip zip_archive old_title replace tag_stack has_checker de_list run_method
);

use CATS::Problem::Tests;
use CATS::Problem::Repository;


sub checker_type_names
{{
    legacy => $cats::checker,
    testlib => $cats::testlib_checker,
    partial => $cats::partial_checker,
}}


sub new
{
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}


sub clear
{
    my CATS::Problem $self = shift;
    undef $self->{$_} for keys %CATS::Problem::FIELDS;
    $self->{$_} = {} for qw(tests test_defaults testsets samples objects keywords);
    $self->{$_} = [] for qw(imports solutions generators modules pictures attachments);
    $self->{gen_groups} = {};
}


sub encoded_import_log
{
    my CATS::Problem $self = shift;
    return escape_html($self->{import_log});
}


sub get_repo
{
    my ($id, $sha) = @_;
    my ($db_id, $db_sha) = $dbh->selectrow_array(qq~
       SELECT repo, commit_sha FROM problems WHERE id = ?~, undef, $id);
    my $p = cats_dir() . $cats::repos_dir;
    die 'Repository not found' unless (($db_id ne '' && -d "$p$db_id/") || -d "$p$id/");
    return $db_id ne '' ? ($db_id, $db_sha) : ($id, $sha // '');
}


sub show_commit
{
    my ($pid) = get_repo(@_);
    return CATS::Problem::Repository->new(dir => cats_dir() . "$cats::repos_dir$pid/")->commit_info($_[1]);
}


sub get_log
{
    my ($pid, $sha) = get_repo(@_);
    return CATS::Problem::Repository->new(dir => cats_dir() . "$cats::repos_dir$pid/")->log(sha => $sha);
}


sub add_history
{
    (my CATS::Problem $self, my $fname) = @_;
    my $problem = {
        zip => $fname,
        id => $self->{id},
        title => $self->{problem}{title},
        author => $self->{problem}{author},
    };
    my $path = cats_dir() . $cats::repos_dir;
    my $p = CATS::Problem::Repository->new(
        dir => "$path/$self->{id}/",
        logger => $self,
        author_name => $git_author_name,
        author_email => $git_author_email
    );
    if ($self->{replace}) {
        my ($repo_id, $sha) = get_repo($self->{id});
        $p->move_history(from => "$path/$repo_id/", sha => $sha) unless $repo_id == $self->{id};
        $p->add($problem);
        $dbh->do(qq~
            UPDATE problems SET repo = ?, commit_sha = ? WHERE id = ?~, undef, '', '', $self->{id})
            unless $repo_id == $self->{id};
        $dbh->commit;
    }
    else {
        $p->init($problem);
    }
}


sub load
{
    my CATS::Problem $self = shift;
    (my $fname, $self->{contest_id}, $self->{id}, $self->{replace}) = @_;

    eval {
        CATS::BinaryFile::load($fname, \$self->{zip_archive})
            or $self->error("open '$fname' failed: $!");

        $self->{zip} = Archive::Zip->new();
        $self->{zip}->read($fname) == AZ_OK
            or $self->error("read '$fname' failed -- probably not a zip archive");

        my @xml_members = $self->{zip}->membersMatching('.*\.xml$');

        $self->error('*.xml not found') if !@xml_members;
        $self->error('found several *.xml in archive') if @xml_members > 1;

        $self->{tag_stack} = [];
        my $parser = new XML::Parser::Expat;
        $parser->setHandlers(
            Start => sub { $self->on_start_tag(@_) },
            End => sub { $self->on_end_tag(@_) },
            Char => sub { ${$self->{stml}} .= CATS::Utils::escape_xml($_[1]) if $self->{stml} },
            XMLDecl => sub { $self->{encoding} = $_[2] },
        );
        $parser->parse($self->read_member($xml_members[0]));
    };

    if ($@) {
        $dbh->rollback unless $self->{debug};
        $self->note("Import failed: $@");
        return -1;
    }
    else {
        unless ($self->{debug}) {
            $dbh->commit;
            eval { $self->add_history($fname); };
            $self->note("Warning: $@") if $@;
        }
        $self->note('Success import');
        return 0;
    }
}


sub delete
{
    my ($cpid) = @_;
    $cpid or die;

    my ($pid, $old_contest, $title, $origin_contest) = $dbh->selectrow_array(q~
        SELECT CP.problem_id, CP.contest_id, P.title, P.contest_id AS orig
        FROM contest_problems CP INNER JOIN problems P ON CP.problem_id = P.id WHERE CP.id = ?~, undef,
        $cpid) or return;

    my ($ref_count) = $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM contest_problems WHERE problem_id = ?~, undef, $pid);
    if ($ref_count > 1) {
        # If at least one contest still references the problem, move all submissions
        # to the "origin" contest. Problem can be removed from the origin only with zero links.
        # To work around this limitation, move the problem to a different contest before deleting.
        $old_contest != $origin_contest or return msg(1136);
        $dbh->do(q~DELETE FROM contest_problems WHERE id = ?~, undef, $cpid);
        $dbh->do(q~
            UPDATE reqs SET contest_id = ? WHERE problem_id = ? AND contest_id = ?~, undef,
            $origin_contest, $pid, $old_contest);
    }
    else {
        # Cascade into contest_problems and reqs.
        $dbh->do(q~DELETE FROM problems WHERE id = ?~, undef, $pid);
        CATS::Problem::Repository->new(dir => cats_dir() . "$cats::repos_dir$pid/")->delete;
    }

    CATS::StaticPages::invalidate_problem_text(cid => $old_contest, cpid => $cpid);
    $dbh->commit;
    msg(1022, $title, $ref_count - 1);
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

    my $check_order = sub {
        my ($objects, $name) = @_;
        for (1 .. keys %$objects) {
            exists $objects->{$_} or $self->error("Missing $name #$_");
        }
    };

    $self->apply_test_defaults;
    $check_order->($self->{tests}, 'test');
    my @t = values %{$self->{tests}};
    for (@t) {
        my $error = validate_test($_) or next;
        $self->error("$error for test $_->{rank}");
    }

    my @without_points = map $_->{rank}, grep !defined $_->{points}, @t;
    $self->warning('Points not defined for tests: ' . join ',', @without_points)
        if @without_points && @without_points != @t;

    $check_order->($self->{samples}, 'sample');

    $self->{run_method} ||= $cats::rm_default;
}


sub required_attributes
{
    my CATS::Problem $self = shift;
    my ($el, $attrs, $names) = @_;
    for (@$names) {
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
    my ($name) = @_;
    defined $name or return undef;
    defined $self->{objects}->{$name}
        or $self->error(
            "Undefined object reference: '$name' in " . join '/', @{$self->{tag_stack}}
        );
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

    if ($self->{stml}) {
        if ($el eq 'include') {
            my $name = $atts{src} or
                return $self->error(q~Missing required 'src' attribute of 'include' tag~);
            my $member = $self->{zip}->memberNamed($name)
                or $self->error("Invalid 'include' reference: '$name'");
            ${$self->{stml}} .= Encode::decode($self->{encoding}, $self->read_member($member));
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
    my CATS::Problem $self = shift;
    my ($p, $el, %atts) = @_;

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


sub start_tag_Problem
{
    (my CATS::Problem $self, my $atts) = @_;

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

    my $ot = $self->{old_title};
    $self->error(sprintf
        "Unexpected problem rename from: $ot to: $self->{problem}->{title}",
    ) if $ot && $self->{problem}->{title} ne $ot;
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


sub start_tag_Attachment
{
    (my CATS::Problem $self, my $atts) = @_;

    push @{$self->{attachments}},
        $self->set_named_object($atts->{name}, {
            id => new_id,
            $self->read_member_named(name => $atts->{src}, kind => 'attachment'),
            name => $atts->{name}, file_name => $atts->{src}, refcount => 0
        });
}


sub problem_source_common_params
{
    (my CATS::Problem $self, my $atts, my $kind) = @_;
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
    (my CATS::Problem $self, my $atts) = @_;

    my $sol = $self->set_named_object($atts->{name}, {
        $self->problem_source_common_params($atts, 'solution'),
        checkup => $atts->{checkup},
    });
    push @{$self->{solutions}}, $sol;
}


sub start_tag_Checker
{
    (my CATS::Problem $self, my $atts) = @_;

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


sub create_generator
{
    (my CATS::Problem $self, my $p) = @_;

    return $self->set_named_object($p->{name}, {
        $self->problem_source_common_params($p, 'generator'),
        outputFile => $p->{outputFile},
    });
}


sub end_tag_FormalInput
{
    (my CATS::Problem $self, my $atts) = @_;
    my $parser_err = FormalInput::parserValidate(${$self->{stml}});
    #$self->note($self->{formal_input});
    if ($parser_err) {
        my $s = FormalInput::errorMessageByCode(FormalInput::getErrCode($parser_err));
        my $l = FormalInput::getErrLine($parser_err);
        my $p = FormalInput::getErrPos($parser_err);
        $self->error("FormalInput: $s. Line: $l. Pos: $p.");
    }
    else {
        $self->note('FormalInput OK.');
    }
    $self->end_stml;
}


sub end_tag_JsonData
{
    (my CATS::Problem $self, my $atts) = @_;
    #$self->note($self->{formal_input});
    ${$self->{stml}} = Encode::encode_utf8(${$self->{stml}});
    eval { decode_json(${$self->{stml}}) };
    if ($@) {
        $self->error("JsonData: $@");
    }
    else {
        $self->note('JsonData OK.');
    }
    $self->end_stml;
}


sub start_tag_Generator
{
    (my CATS::Problem $self, my $atts) = @_;
    push @{$self->{generators}}, $self->create_generator($atts);
}


sub start_tag_GeneratorRange
{
    (my CATS::Problem $self, my $atts) = @_;
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


sub import_one_source
{
    (my CATS::Problem $self, my $guid, my $name, my $type) = @_;
    push @{$self->{imports}}, my $import = { guid => $guid, name => $name };
    my ($src_id, $stype) = $self->{debug} ? (undef, undef) : $dbh->selectrow_array(qq~
        SELECT id, stype FROM problem_sources WHERE guid = ?~, undef, $guid);

    !$type || ($type = $import->{type} = module_types()->{$type})
        or $self->error("Unknown import source type: $type");

    if ($src_id) {
        !$type || $stype == $type || $cats::source_modules{$stype} == $type
            or $self->error("Import type check failed for guid='$guid' ($type vs $stype)");
        $self->checker_added if $cats::source_modules{$stype} == $cats::checker_module;
        $import->{src_id} = $src_id;
        $self->note("Imported source from guid='$guid'");
    }
    else {
        $self->warning("Import source not found for guid='$guid'");
    }

}


sub start_tag_Import
{
    (my CATS::Problem $self, my $atts) = @_;

    (my $guid, my @nt) = @$atts{qw(guid name type)};
    if ($guid =~ /\*/) {
        $guid =~ s/%/\\%/g;
        $guid =~ s/\*/%/g;
        my $guids = $dbh->selectcol_arrayref(qq~
            SELECT guid FROM problem_sources WHERE guid LIKE ? ESCAPE '\\'~, undef, $guid);
        $self->import_one_source($_, @nt) for @$guids;
    }
    else {
        # обычный случай -- прямая ссылка
        $self->import_one_source($guid, @nt);
    }
}


sub get_imported_id
{
    (my CATS::Problem $self, my $name) = @_;
    for (@{$self->{imports}}) {
        return $_->{src_id} if $name eq ($_->{name} || '');
    }
    undef;
}


sub start_tag_Sample
{
    (my CATS::Problem $self, my $atts) = @_;

    my $r = $atts->{rank};
    $self->error("Duplicate sample $r") if defined $self->{samples}->{$r};

    $self->{current_sample} = $self->{samples}->{$r} =
        { sample_id => new_id, rank  => $r };
}


sub end_tag_Sample
{
    my CATS::Problem $self = shift;
    undef $self->{current_sample};
}


sub sample_in_out
{
    (my CATS::Problem $self, my $atts, my $in_out) = @_;
    if (my $src = $atts->{src}) {
        my $member = $self->{zip}->memberNamed($src)
            or $self->error("Invalid sample $in_out reference: '$src'");
        $self->{current_sample}->{$in_out} = $self->read_member($member, $self->{debug});
    }
    else {
        $self->{stml} = \$self->{current_sample}->{$in_out};
    }
}


sub start_tag_SampleIn { $_[0]->sample_in_out($_[1], 'in_file'); }
sub start_tag_SampleOut { $_[0]->sample_in_out($_[1], 'out_file'); }


sub start_tag_Keyword
{
    (my CATS::Problem $self, my $atts) = @_;

    my $c = $atts->{code};
    !defined $self->{keywords}->{$c}
        or $self->warning("Duplicate keyword '$c'");
    $self->{keywords}->{$c} = 1;
}


sub start_tag_Testset
{
    (my CATS::Problem $self, my $atts) = @_;
    my $n = $atts->{name};
    $self->{testsets}->{$n} and $self->error("Duplicate testset '$n'");
    $self->parse_test_rank($atts->{tests});
    $self->{testsets}->{$n} = {
        id => new_id, map { $_ => $atts->{$_} } qw(name tests points comment hideDetails) };
    $self->{testsets}->{$n}->{hideDetails} ||= 0;
    $self->note("Testset $n added");
}


sub start_tag_Run
{
    (my CATS::Problem $self, my $atts) = @_;
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
    (my CATS::Problem $self, my $member, my $debug) = @_;
    $debug and return $member->fileName();

    $member->desiredCompressionMethod(COMPRESSION_STORED);
    my $status = $member->rewindData();
    $status == AZ_OK or $self->error("code $status");

    my $data = '';
    while (!$member->readIsDone()) {
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
    $dbh->do(qq~
        DELETE FROM $_ WHERE problem_id = ?~, undef,
        $pid)
        for qw(
            pictures samples tests testsets problem_sources
            problem_sources_import problem_keywords problem_attachments);
}


sub end_tag_Problem
{
    my CATS::Problem $self = shift;

    $self->validate;

    return if $self->{debug};

    delete_child_records($self->{id}) if $self->{replace};

    my $sql = $self->{replace}
    ? q~
        UPDATE problems
        SET
            contest_id=?,
            title=?, lang=?, time_limit=?, memory_limit=?, difficulty=?, author=?, input_file=?, output_file=?,
            statement=?, pconstraints=?, input_format=?, output_format=?, formal_input=?, json_data=?, explanation=?, zip_archive=?,
            upload_date=CURRENT_TIMESTAMP, std_checker=?, last_modified_by=?,
            max_points=?, hash=NULL, run_method=?
        WHERE id = ?~
    : q~
        INSERT INTO problems (
            contest_id,
            title, lang, time_limit, memory_limit, difficulty, author, input_file, output_file,
            statement, pconstraints, input_format, output_format, formal_input, json_data, explanation, zip_archive,
            upload_date, std_checker, last_modified_by,
            max_points, id, run_method
        ) VALUES (
            ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP,?,?,?,?,?
        )~;

    my $c = $dbh->prepare($sql);
    my $i = 1;
    $c->bind_param($i++, $self->{contest_id});
    $c->bind_param($i++, $self->{problem}->{$_})
        for qw(title lang time_limit memory_limit difficulty author input_file output_file);
    $c->bind_param($i++, $self->{$_}, { ora_type => 113 })
        for qw(statement constraints input_format output_format formal_input json_data explanation zip_archive);
    $c->bind_param($i++, $self->{problem}->{std_checker});
    $c->bind_param($i++, $CATS::Misc::uid);
    $c->bind_param($i++, $self->{problem}->{max_points});
    $c->bind_param($i++, $self->{id});
    $c->bind_param($i++, $self->{run_method});
    $c->execute;

    $self->insert_problem_content;
}


sub get_de_id
{
    my CATS::Problem $self = shift;
    my ($code, $path) = @_;

    $self->{de_list} ||= CATS::DevEnv->new($dbh);

    my $de;
    if (defined $code) {
        $de = $self->{de_list}->by_code($code)
            or $self->error("Unknown DE code: '$code' for source: '$path'");
    }
    else {
        $de = $self->{de_list}->by_file_extension($path)
            or $self->error("Can't detect de for source: '$path'");
        $self->note("Detected DE: '$de->{description}' for source: '$path'");
    }
    return $de->{id};
}


sub insert_problem_source
{
    my CATS::Problem $self = shift;
    my %p = @_;
    use Carp;
    my $s = $p{source_object} or confess;

    if ($s->{guid}) {
        my $dup_id = $dbh->selectrow_array(qq~
            SELECT problem_id FROM problem_sources WHERE guid = ?~, undef, $s->{guid});
        $self->warning("Duplicate guid with problem $dup_id") if $dup_id;
    }
    my $c = $dbh->prepare(qq~
        INSERT INTO problem_sources (
            id, problem_id, de_id, src, fname, stype, input_file, output_file, guid,
            time_limit, memory_limit
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?)~);

    $c->bind_param(1, $s->{id});
    $c->bind_param(2, $self->{id});
    $c->bind_param(3, $self->get_de_id($s->{de_code}, $s->{path}));
    $c->bind_param(4, $s->{src}, { ora_type => 113 });
    $c->bind_param(5, $s->{path});
    $c->bind_param(6, $p{source_type});
    $c->bind_param(7, $s->{inputFile});
    $c->bind_param(8, $s->{outputFile});
    $c->bind_param(9, $s->{guid});
    $c->bind_param(10, $s->{time_limit});
    $c->bind_param(11, $s->{memory_limit});
    $c->execute;

    my $g = $s->{guid} ? ", guid=$s->{guid}" : '';
    $self->note("$p{type_name} '$s->{path}' added$g");
}


sub insert_problem_content
{
    my CATS::Problem $self = shift;

    my $p = $self->{problem};

    $self->{has_checker} or $self->error('No checker specified');

    if ($p->{std_checker}) {
        $self->note("Checker: $p->{std_checker}");
    }
    elsif (my $c = $self->{checker}) {
        $self->insert_problem_source(
            source_object => $c, type_name => 'Checker',
            source_type => checker_type_names->{$c->{style}},
        );
    }

    for(@{$self->{generators}}) {
        $self->insert_problem_source(
            source_object => $_, source_type => $cats::generator, type_name => 'Generator');
    }

    for(@{$self->{solutions}}) {
        $self->insert_problem_source(
            source_object => $_, type_name => 'Solution',
            source_type => $_->{checkup} ? $cats::adv_solution : $cats::solution);
    }

    for (@{$self->{modules}}) {
        $self->insert_problem_source(
            source_object => $_, source_type => $_->{type_code},
            type_name => "Module for $_->{type}");
    }

    for (@{$self->{imports}}) {
        $dbh->do(q~
            INSERT INTO problem_sources_import (problem_id, guid) VALUES (?, ?)~, undef,
            $self->{id}, $_->{guid});
    }

    for my $ts (values %{$self->{testsets}}) {
        $dbh->do(q~
            INSERT INTO testsets (id, problem_id, name, tests, points, comment, hide_details)
            VALUES (?, ?, ?, ?, ?, ?, ?)~, undef,
            $ts->{id}, $self->{id}, @{$ts}{qw(name tests points comment hideDetails)});
    }

    my $c = $dbh->prepare(qq~
        INSERT INTO pictures(id, problem_id, extension, name, pic)
            VALUES (?,?,?,?,?)~);
    for (@{$self->{pictures}}) {

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
        INSERT INTO problem_attachments(id, problem_id, name, file_name, data)
            VALUES (?,?,?,?,?)~);
    for (@{$self->{attachments}}) {

        $c->bind_param(1, $_->{id});
        $c->bind_param(2, $self->{id});
        $c->bind_param(3, $_->{name});
        $c->bind_param(4, $_->{file_name});
        $c->bind_param(5, $_->{src}, { ora_type => 113 });
        $c->execute;

        $self->note("Attachment '$_->{path}' added");
        $_->{refcount}
            or $self->warning("No references to attachment '$_->{path}'");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO tests (
            problem_id, rank, generator_id, param, std_solution_id, in_file, out_file,
            points, gen_group
        ) VALUES (?,?,?,?,?,?,?,?,?)~
    );

    for (sort { $a->{rank} <=> $b->{rank} } values %{$self->{tests}}) {
        $c->bind_param(1, $self->{id});
        $c->bind_param(2, $_->{rank});
        $c->bind_param(3, $_->{generator_id});
        $c->bind_param(4, $_->{param});
        $c->bind_param(5, $_->{std_solution_id} );
        $c->bind_param(6, $_->{in_file}, { ora_type => 113 });
        $c->bind_param(7, $_->{out_file}, { ora_type => 113 });
        $c->bind_param(8, $_->{points});
        $c->bind_param(9, $_->{gen_group});
        $c->execute
            or $self->error("Can not add test $_->{rank}: $dbh->errstr");
        $self->note("Test $_->{rank} added");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO samples (problem_id, rank, in_file, out_file)
        VALUES (?,?,?,?)~
    );
    for (values %{$self->{samples}}) {
        $c->bind_param(1, $self->{id});
        $c->bind_param(2, $_->{rank});
        $c->bind_param(3, $_->{in_file}, { ora_type => 113 });
        $c->bind_param(4, $_->{out_file}, { ora_type => 113 });
        $c->execute;
        $self->note("Sample test $_->{rank} added");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO problem_keywords (problem_id, keyword_id) VALUES (?, ?)~);
    for (keys %{$self->{keywords}}) {
        my ($keyword_id) = $dbh->selectrow_array(q~
            SELECT id FROM keywords WHERE code = ?~, undef, $_);
        if ($keyword_id) {
            $c->execute($self->{id}, $keyword_id);
            $self->note("Keyword added: $_");
        }
        else {
            $self->warning("Unknown keyword: $_");
        }
    }
}


1;
