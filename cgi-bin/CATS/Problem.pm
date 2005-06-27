package CATS::Problem;

#use lib './';
use strict;
use Encode;

use CATS::Constants;
use CATS::Misc qw(:all);
use FileHandle;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use XML::Parser::Expat;

my $default_mlimit = 200;

my ($stml, 
    $cid,
    $pid,
    $zip,
    $import_log,
    $zip_archive,
    %problem,
    %objects,
    %solution,
    %checker,
    %generator,
    %generator_range,
    %module,
    %picture,
    %test,
    %test_range,
    %sample,
    %test_rank_array,
    %sample_rank_array,
    $statement,
    $constraints,
    $inputformat,
    $outputformat,
    $user_checker);

my %stml_tags = (
    'ProblemStatement' => \$statement, 
    'ProblemConstraints' => \$constraints,
    'InputFormat' => \$inputformat, 
    'OutputFormat' => \$outputformat 
);


sub note($)
{
    $import_log .= $_[0];
}


sub warning($) 
{
    my $m = 'Warning: ' . shift;
    $import_log .= $m;
}


sub error($) 
{
    $import_log .= 'Error: ' . $_[0];
    die "Unrecoverable error\n";
}


sub start_stml_element
{
    my ($stream, $el, %atts) = @_;
    
    $$stream .= "<$el";
    if ($el eq 'img' && !$atts{'picture'})
    {
        warning "Picture not defined in img element\n";
    }
    for my $name (keys %atts)
    {
        $$stream .= qq~ $name="$atts{$name}"~;
    }
    $$stream .= '>';
}


sub end_element
{
    my ($stream, $el) = @_;    
    $$stream .= "</$el>";
}


sub text
{
    my ($stream, $text) = @_;    
    $$stream .= escape_html $text;
}


sub read_member {
    
    my $member = shift;

    my ($data, $status, $buffer) = "";
    
    $member->desiredCompressionMethod(COMPRESSION_STORED);
    $status = $member->rewindData();
    error "error $status" unless ($status == AZ_OK);

    while (!$member->readIsDone())
    {
        ($buffer, $status) = $member->readChunk();
        error "error $status" if ($status != AZ_OK && $status != AZ_STREAM_END);
        $data .= $$buffer;
    }
    $member->endRead();

    return $data;    
}


sub required_attributes
{
    my ($el, $attrs, $names) = @_;
    for (@$names)
    {
        defined $attrs->{$_}
            or error "$el.$_ not specified\n";
    }
}


# 1 проход
sub stml_text
{
    my ($p, $text) = @_;
    if ($stml) { 
        text($stml, $text); 
    }  
}


sub parse_problem
{
    my ($p, $el, %atts) = @_;

    if ($stml) { 
        start_stml_element($stml, $el, %atts); 
        return; 
    }        
        
    if (defined $stml_tags{$el}) { 
        $stml = $stml_tags{$el}; 
    }

    
    if ($el eq 'Problem')
    {
        required_attributes($el, \%atts, ['title', 'lang', 'tlimit', 'inputFile', 'outputFile']);

        defined $atts{'mlimit'}
            or warning "Problem.mlimit not specified. default: $default_mlimit\n";

        %problem = (
            'title' => $atts{'title'},
            'lang' => $atts{'lang'},
            'time_limit' => $atts{'tlimit'},
            'memory_limit' => ($atts{'mlimit'} or $default_mlimit),
            'difficulty' => $atts{'difficulty'},
            'author' => $atts{'author'},
            'input_file' => $atts{'inputFile'},
            'output_file' => $atts{'outputFile'},       
            'std_checker' => $atts{'stdChecker'}
        );
    }
    elsif ($el eq 'Checker')
    {
        if (defined $user_checker) {
            error "Found several checkers\n";
        }

        $user_checker = 1;
    }    
}


sub problem_insert
{
    my ($p, $el) = @_;

    if (defined $stml_tags{$el}) { $stml = 0; }

    if ($stml) { end_element($stml, $el); return; }     

    if ($el eq 'Problem')
    {   
        my $c = $dbh->prepare(qq~INSERT INTO problems 
            (id, contest_id, title, lang, time_limit, memory_limit, difficulty, author, 
            input_file, output_file, 
                statement, pconstraints, input_format, output_format, 
            zip_archive, upload_date, std_checker) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,CATS_SYSDATE(), ?)~);
        
        $c->bind_param(1, $pid);
        $c->bind_param(2, $cid);
        $c->bind_param(3, $problem{'title'} );
        $c->bind_param(4, $problem{'lang'} );
        $c->bind_param(5, $problem{'time_limit'} );
        $c->bind_param(6, $problem{'memory_limit'} );
        $c->bind_param(7, $problem{'difficulty'} );
        $c->bind_param(8, $problem{'author'} );
        $c->bind_param(9, $problem{'input_file'} );
        $c->bind_param(10, $problem{'output_file'} );
        $c->bind_param(11, $statement, { ora_type => 113 } );
        $c->bind_param(12, $constraints, { ora_type => 113 } );
        $c->bind_param(13, $inputformat, { ora_type => 113 } );
        $c->bind_param(14, $outputformat, { ora_type => 113 } );
        $c->bind_param(15, $zip_archive, { ora_type => 113 } );
        $c->bind_param(16, $problem{'std_checker'} );
        
        $c->execute;

        my $std_checker = $problem{'std_checker'};
        if (defined $user_checker && defined $std_checker)
        {
            error "User checker and standart checker specified\n";
        }

        if (!defined $user_checker && !defined $std_checker)
        {
            error "No checker specified\n";
        }

        if (defined $problem{'std_checker'}) {
            note "Checker: $problem{'std_checker'}\n";
        }
    }
} 


sub problem_update
{
    my ($p, $el) = @_;

    if (defined $stml_tags{$el}) { $stml = 0; }

    if ($stml) { end_element($stml, $el); return; }     

    if ($el eq 'Problem')
    {
        $dbh->do(qq~DELETE FROM pictures WHERE problem_id=?~, {}, $pid) &&
        $dbh->do(qq~DELETE FROM samples WHERE problem_id=?~, {}, $pid) &&
        $dbh->do(qq~DELETE FROM tests WHERE problem_id=?~, {}, $pid) && 
        $dbh->do(qq~DELETE FROM problem_sources WHERE problem_id=?~, {}, $pid) ||
           error "Couldn't update problem\n";
    
        my $c = $dbh->prepare(qq~UPDATE problems 
            SET contest_id=?, title=?, lang=?, time_limit=?, memory_limit=?, difficulty=?, author=?, 
            input_file=?, output_file=?, 
                statement=?, pconstraints=?, input_format=?, output_format=?, 
            zip_archive=?, upload_date=CATS_SYSDATE(), std_checker=? WHERE id=?~);

        $c->bind_param(1, $cid);
        $c->bind_param(2, $problem{'title'} );
        $c->bind_param(3, $problem{'lang'} );
        $c->bind_param(4, $problem{'time_limit'} );
        $c->bind_param(5, $problem{'memory_limit'} );
        $c->bind_param(6, $problem{'difficulty'} );
        $c->bind_param(7, $problem{'author'} );
        $c->bind_param(8, $problem{'input_file'} );
        $c->bind_param(9, $problem{'output_file'} );
        $c->bind_param(10, $statement, { ora_type => 113 } );
        $c->bind_param(11, $constraints, { ora_type => 113 } );
        $c->bind_param(12, $inputformat, { ora_type => 113 } );
        $c->bind_param(13, $outputformat, { ora_type => 113 } );
        $c->bind_param(14, $zip_archive, { ora_type => 113 } );
        $c->bind_param(15, $problem{'std_checker'} );
        $c->bind_param(16, $pid);   

        $c->execute;

        my $std_checker = $problem{'std_checker'};
        if (defined $user_checker && defined $std_checker)
        {
            error "User checker and standart checker specified\n";
        }

        if (!defined $user_checker && !defined $std_checker)
        {
            error "No checker specified\n";
        }

        if (defined $problem{'std_checker'}) {
            note "Checker: $problem{'std_checker'}\n";
        }    
    }
} 


# 2 проход
sub set_object_id 
{
    my ($name, $id) = @_;
    if (!defined $name) { 
        return; 
    }
    error "Duplicate object reference: '$name'\n" if defined $objects{$name};
    $objects{$name} = $id;
}


sub get_object_id 
{
    my $name = shift;
    if (!defined $name) { return undef; }
    error "Undefined object reference: '$name'\n" unless defined $objects{$name};

    return $objects{$name};
}


sub get_source_de 
{
    my $fname = shift;

    my ($vol, $dir, $file_name, $name, $ext) = split_fname($fname);
    
    my $c = $dbh->prepare(qq~SELECT id, code, description, file_ext FROM default_de~);
    $c->execute;    
    while (my ($did, $code, $description, $file_ext) = $c->fetchrow_array)
    {
        my @ext_list = split(/\;/, $file_ext);

        foreach my $i (@ext_list) {
            if ($i ne '' && $i eq $ext) {
                return ($did, $description);
            }
        }
    }
    
    return undef;
}


sub get_de_id 
{
    my $code = shift;
    my $path = shift;
    if (defined $code)
    {
        my $did = $dbh->selectrow_array(qq~SELECT id FROM default_de WHERE code=?~, {}, $code);
        unless (defined $did) {
            error "Unknown de code: '$code' for source: '$path'\n";
        }
        return $did;
    } 
    else 
    {
        my ($did, $de_desc) = get_source_de($path);
        if (defined $did) {
            note "Detected de: '$de_desc' for source: '$path'\n";
            return $did;
        }
        else {
            error "Can't detect de for source: '$path'\n";
        }
    }
    return undef;
}
                    

sub interpolate_rank { apply_test_rank(@_); }

sub apply_test_rank
{
    my ($v, $rank) = @_;
    $v =~ s/%n/$rank/g;
    $v =~ s/%0n/sprintf("%02d", $rank)/eg;

    $v;
}


sub read_member_named
{
    my %p = @_;
    my $member = $zip->memberNamed($p{name}) 
        or error "Invalid $p{kind} reference: '$p{name}'\n";

    return
        ('src' => read_member($member), 'path' => $p{name});
}

sub create_generator
{
    my %p = @_;
    
    my $id = new_id;
    set_object_id($p{name}, $id);

    return (  
        'id' => $id,
        read_member_named(name => $p{src}, kind => 'generator'),
        'de_code' => $p{de_code},
        'outputFile' => $p{'outputFile'},
    );
}


sub parse_problem_content
{
    my ($p, $el, %atts) = @_;

    if ($el eq 'Picture')
    {
        required_attributes($el, \%atts, ['src', 'name']);

        my @p = split(/\./, $atts{'src'}); my $ext = $p[-1];
        error "Invalid image extension\n" if ($ext eq '') ;
        
        %picture = (
            'id' => new_id,
            read_member_named(name => $atts{'src'}, kind => 'picture'),
            'name' => $atts{'name'},
            'ext' => $ext
        )
    }

    if ($el eq 'Solution')
    {
        required_attributes($el, \%atts, ['src', 'name']);

        my $id = new_id;
        set_object_id($atts{'name'}, $id);

        %solution = (   
            'id' => $id,
            read_member_named(name => $atts{'src'}, kind => 'solution'),
            'de_code' => $atts{'de_code'},
            'checkup' => $atts{'checkup'}       
        )
    }

    if ($el eq 'Checker')
    {
        required_attributes($el, \%atts, ['src']);

        my $style = $atts{'style'} || 'legacy';
        for ($style)
        {
            /^legacy$/ && do { note "WARNING: Legacy checker found!\n"; last; };
            /^testlib$/ && last;
            error "Unknown checker style (must be either 'legacy' or 'testlib')\n";
        }
        
        %checker = (    
            'id' => new_id,
            read_member_named(name => $atts{'src'}, kind => 'checker'),
            'de_code' => $atts{'de_code'},
            'style' => $style
        )
    }

    if ($el eq 'Generator')
    {
        required_attributes($el, \%atts, ['src', 'name']);
        %generator = create_generator(%atts);
    }

    if ($el eq 'GeneratorRange')
    {
        required_attributes($el, \%atts, ['src', 'name', 'from', 'to']);
        %generator_range = (  
            'path' => $atts{'src'},
            'de_code' => $atts{'de_code'},
            'elements' => {}
        );
        for ($atts{'from'} .. $atts{'to'})
        {
            $generator_range{'elements'}->{$_} = { create_generator(
                name => interpolate_rank($atts{'name'}, $_),
                src => interpolate_rank($atts{'src'}, $_),
                de_code => $atts{'de_code'},
                'outputFile' => $atts{'outputFile'},
            ) };
        }
    }

    if ($el eq 'Module')
    {
        required_attributes($el, \%atts, ['src', 'de_code', 'type']);

        my $types = {
          'checker' => $cats::checker_module,
          'solution' => $cats::solution_module,
          'generator' => $cats::generator_module,
        };
        exists $types->{$atts{'type'}}
            or error "Unknown module type: $atts{'type'}\n";
        %module = (
            'id' => new_id,
            read_member_named(name => $atts{'src'}, kind => 'module'),
            'de_code' => $atts{'de_code'},
            'type' => $atts{'type'},
            'type_code' => $types->{$atts{'type'}},
        );
    }

    if ($el eq 'Test')
    {
        required_attributes($el, \%atts, ['rank']);

        for ($atts{'rank'})
        {
            /\d+/ or error "Bad rank: '$_'\n";
            !defined $test_rank_array{$_}
                or error "Duplicate test $_\n";
            $test_rank_array{$_} = 1;
        }

        %test = (
            'rank' => $atts{'rank'},
            'points' => $atts{'points'},
            'in' => 1
        );

    }

    if ($el eq 'TestRange')
    {
        required_attributes($el, \%atts, ['from', 'to']);

        $atts{'from'} <= $atts{'to'}
            or error 'TestRange.from > TestRange.to';

        %test_range = (
            'from' => $atts{'from'},
            'to' => $atts{'to'},
            'points' => $atts{'points'},
            'in' => 1
        );

        for ($atts{'from'}..$atts{'to'})
        {
            !defined $test_rank_array{$_}            
                or error "Duplicate test $_\n";
            $test_rank_array{$_} = 1;
        }
    }   


    if ($el eq 'In' && $test{in})
    {       
        if (defined $atts{'src'}) 
        {
            #$test{'in_file'} = read_member_named(name => $atts{'src'}, kind => 'test input file'),
            my $member = $zip->memberNamed($atts{'src'});
            error "Invalid test input file reference: '$atts{'src'}'\n" if (!defined $member);
            $test{'in_file'} = read_member($member);                           
        }
        elsif (defined $atts{'use'})
        {
            $test{'generator_id'} = get_object_id($atts{'use'});            
            $test{'param'} = $atts{'param'};
        }
        else {
            error "Test input file not specified for test $test{rank}\n";
        }
    }

    if ($el eq 'Out' && $test{in})
    {
        if (defined $atts{'src'}) {
            my $member = $zip->memberNamed($atts{'src'}) 
                or error "Invalid test output file reference: '$atts{'src'}'\n";
            $test{'out_file'} = read_member($member);
        }
        elsif (defined $atts{'use'}) {
            $test{'std_solution_id'} = get_object_id($atts{'use'});
        }
        else {
            error "Test output file not specified $test{rank}\n";
        }
    }       

    if ($el eq 'In' && $test_range{in})
    {       
        if (defined $atts{'src'}) 
        {
            $test_range{'in_src'} = $atts{'src'};
        }
        elsif (defined $atts{'use'})
        {
            $test_range{'generator'} = $atts{'use'};            
            $test_range{'param'} = $atts{'param'};
        }
        else {
            error "Test input file not specified for test range\n";
        }
    }


    if ($el eq 'Out' && $test_range{in})
    {
        if (defined $atts{'src'}) {
            $test_range{'out_src'} = $atts{'src'};
        }
        elsif (defined $atts{'use'}) {
            $test_range{'std_solution'} = $atts{'use'};
        }
        else {
            error "Test output file not specified for test range\n";
        }
    }       


    if ($el eq 'Sample')
    {
        required_attributes($el, \%atts, ['rank']);

        if (defined $sample_rank_array{$atts{'rank'}}) {            
            error "Duplicate sample $atts{'rank'}\n";
        }

        %sample = (
            'sample_id' => new_id,
            'rank'  => $atts{'rank'},
        );

        $sample_rank_array{$atts{'rank'}} = 1;
    }   

    if ($el eq 'SampleIn')
    {
        $sample{'in'} = 1;
        $sample{'in_file'} = "";
    }

    if ($el eq 'SampleOut')
    {
        $sample{'out'} = 1;
        $sample{'out_file'} = "";
    }
}


sub problem_content_text 
{
    my ($p, $text) = @_;

    if ($sample{'in'}) {
        $sample{'in_file'} .= $text;
    }

    if ($sample{'out'}) {
        $sample{'out_file'} .= $text;
    }       
}

sub insert_problem_source
{
  my %p = @_;
  my $s = $p{source_object} or die;
  
  my $c = $dbh->prepare(qq~INSERT INTO problem_sources
      (id, problem_id, de_id, src, fname, stype, input_file, output_file) VALUES (?,?,?,?,?,?,?,?)~);

  $c->bind_param(1, $s->{'id'});
  $c->bind_param(2, $pid);
  $c->bind_param(3, get_de_id($s->{'de_code'}, $s->{'path'}));
  $c->bind_param(4, $s->{'src'}, { ora_type => 113 });
  $c->bind_param(5, $s->{'path'});
  $c->bind_param(6, $p{source_type});
  $c->bind_param(7, $s->{'inputFile'});
  $c->bind_param(8, $s->{'outputFile'});
  $c->execute;
}


sub insert_problem_content
{
    my ($p, $el) = @_;

    if ($el eq 'Generator')
    {
        insert_problem_source(source_object => \%generator, source_type => $cats::generator);

        note "Generator '$generator{'path'}' added\n";
        %generator = ();
    }
    if ($el eq 'GeneratorRange')
    {
        for (values %{$generator_range{'elements'}})
        {
            insert_problem_source(source_object => $_, source_type => $cats::generator);
            note "Generator '$_->{'path'}' added\n";
        }
        %generator_range = ();
    }

    if ($el eq 'Solution')
    {
        insert_problem_source(
            source_object => \%solution,
            source_type => (defined $solution{'checkup'} && $solution{'checkup'} == 1) ?
                $cats::adv_solution : $cats::solution
        );

        note "Solution '$solution{'path'}' added\n";
        %solution = ();
    }

    if ($el eq 'Checker')
    {
        insert_problem_source(
            source_object => \%checker,
            source_type => ($checker{style} eq 'legacy' ? $cats::checker : $cats::testlib_checker)
        );

        note "Checker '$checker{'path'}' added\n";
        %checker = ();
    }

    if ($el eq 'Module')
    {
        insert_problem_source(source_object => \%module, source_type => $module{'type_code'});

        note "Module '$module{'path'}' for $module{'type'} added\n";
        %module = ();
    }

    if ($el eq 'Picture')
    {
        my $c = $dbh->prepare(qq~INSERT INTO pictures
        (id, problem_id, extension, name, pic) VALUES (?,?,?,?,?)~);

        $c->bind_param(1, $picture{'id'});     
        $c->bind_param(2, $pid);
        $c->bind_param(3, $picture{'ext'});
        $c->bind_param(4, $picture{'name'} );
        $c->bind_param(5, $picture{'src'}, { ora_type => 113 });
        $c->execute;

        note "Picture '$picture{'path'}' added\n";
        %picture = ();
    }                             

    if ($el eq 'Test')
    {
        my $c = $dbh->prepare(qq~
            INSERT INTO tests (
                problem_id, rank, generator_id, param, std_solution_id, in_file, out_file, points
            ) VALUES (?,?,?,?,?,?,?,?)~
        );
            
        $c->bind_param(1, $pid);
        $c->bind_param(2, $test{'rank'});
        $c->bind_param(3, $test{'generator_id'});
        $c->bind_param(4, $test{'param'});
        $c->bind_param(5, $test{'std_solution_id'} );
        $c->bind_param(6, $test{'in_file'}, { ora_type => 113 });
        $c->bind_param(7, $test{'out_file'}, { ora_type => 113 });
        $c->bind_param(8, $test{'points'});
        eval {
    	    $c->execute;
        };
        if ($@) {
            error "Can not add test $test{'rank'}: $@";
        }

        note "Test $test{'rank'} added\n";
        %test = ();
    }

    if ($el eq 'TestRange')
    {
        for my $rank ($test_range{from}..$test_range{to})
        {
            my $in_file = undef;
            if (defined $test_range{in_src})
            {
                my $in_src = apply_test_rank($test_range{in_src}, $rank);

                my $member = $zip->memberNamed($in_src)
                    or error "Invalid test input file reference: '$in_src'\n";
                $in_file = read_member($member);            
            }        

            my $out_file = undef;
            if (defined $test_range{out_src})
            {
                my $out_src = apply_test_rank($test_range{out_src}, $rank);

                my $member = $zip->memberNamed($out_src)
                    or error "Invalid test output file reference: '$out_src'\n";
                $out_file = read_member($member);
            }
               
            my $param = apply_test_rank($test_range{'param'}, $rank);
            my $gen = apply_test_rank($test_range{'generator'}, $rank);
            my $sol = apply_test_rank($test_range{'std_solution'}, $rank);
            
            my $c = $dbh->prepare(qq~
                INSERT INTO tests (
                    problem_id, rank, generator_id, param, std_solution_id, in_file, out_file, points
                ) VALUES (?,?,?,?,?,?,?,?)~
            );
               
            $c->bind_param(1, $pid);
            $c->bind_param(2, $rank);
            $c->bind_param(3, get_object_id($gen));
            $c->bind_param(4, $param);
            $c->bind_param(5, get_object_id($sol));
            $c->bind_param(6, $in_file, { ora_type => 113 });
            $c->bind_param(7, $out_file, { ora_type => 113 });
            $c->bind_param(8, $test_range{points});
            $c->execute;

            note "Test $rank added\n";
        }
        %test_range = ();
    }

    if ($el eq 'SampleIn')
    {
        delete $sample{'in'};
    }

    if ($el eq 'SampleOut')
    {
        delete $sample{'out'};
    }

    if ($el eq 'Sample')
    {
        my $c = $dbh->prepare(qq~
            INSERT INTO samples (problem_id, rank, in_file, out_file)
            VALUES (?,?,?,?)~
        );
            
        $c->bind_param(1, $pid);
        $c->bind_param(2, $sample{'rank'});
        $c->bind_param(3, $sample{'in_file'}, { ora_type => 113 });
        $c->bind_param(4, $sample{'out_file'}, { ora_type => 113 });
        $c->execute;

        note "Sample test $sample{'rank'} added\n";

        %sample = ();
    }
} 


sub clear_globals 
{
    $stml = 0;
    $import_log = '';
    $zip = undef;
    $user_checker = undef;

    %problem = ();
    %objects = ();
    %solution = ();
    %checker = ();
    %generator = ();
    %generator_range = ();
    %module = ();
    %picture = ();
    %test = ();
    %test_range = ();
    %test_rank_array = ();
    %sample_rank_array = ();

    $statement = $constraints = $inputformat = $outputformat = undef;
}


sub verify_test_order
{
    my @order;
    foreach (keys %test_rank_array) {
        push @order, $_;
    }

    if ($#order < 0)
    {
	error "Empty test set\n";
    }

    @order = sort { $a <=> $b } @order;
    for (0..$#order) {           
        if ($order[$_] != $_ + 1) {
            error "Missing test #".($_ + 1)."\n";
        }
    }   

    @order = ();
    foreach (keys %sample_rank_array) {
        push @order, $_;
    }

    @order = sort { $a <=> $b } @order;
    for (0..$#order) {
        if ($order[$_] != $_ + 1) {
            error "Missing sample #".($_ + 1)."\n";
        }
    }
}


sub import_problem
{
    my ($fname, $replace);

    $fname = shift;
    $cid = shift;    
    $pid = shift;
    $replace = shift;

    clear_globals;
    eval 
    {
        unless (open FILE, "<$fname") 
        {
            error "open '$fname' failed: $!\n"; 
            return (undef, $import_log);
        };
          
        binmode(FILE, ':raw');

        $zip_archive = '';
        
        my $buffer;
        while (sysread(FILE, $buffer, 4096)) {
            $zip_archive .= $buffer;
        }
    
        close FILE;    
                    
        $zip = Archive::Zip->new();
        error "read '$fname' failed -- probably not a zip archive\n"
            unless ($zip->read($fname) == AZ_OK);

        my @xml_members = $zip->membersMatching('.*\.xml');

        error "*.xml not found\n" if (!@xml_members);
        error "found severl *.xml in archive\n" if (@xml_members > 1);

        my $member = $xml_members[0];
        my $xml_doc = read_member($member);

        $stml = 0;
    
        # первый проход
        my $parser = new XML::Parser::Expat;

        if (!$replace) {
            $parser->setHandlers(
                    'Start' => \&parse_problem,
                    'End'   => \&problem_insert,
                    'Char'  => \&stml_text);
            $parser->parse($xml_doc); 
        } 
        else
        {
            $parser->setHandlers(
                    'Start' => \&parse_problem,
                    'End'   => \&problem_update,
                    'Char'  => \&stml_text);
            $parser->parse($xml_doc);   
        } 

        # второй проход
        $parser = new XML::Parser::Expat;
        $parser->setHandlers(
                    'Start' => \&parse_problem_content,
                    'End'   => \&insert_problem_content,
                    'Char'  => \&problem_content_text);
        $parser->parse($xml_doc);


        verify_test_order;
    };

    print $@;
    
    my $res;    
    if ($@ eq '') {
        $dbh->commit;
        note "Success\n";
        $res = 0;
    }
    else {
        $dbh->rollback;
        $res = -1;
        note "Import failed: $@\n";
    }

    return ($res, $import_log);
}

1;


