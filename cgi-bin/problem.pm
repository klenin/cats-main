package problem;

use lib './';
use strict;
use Encode;

use cats;
use cats_misc qw(:all);
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
    "ProblemStatement" => \$statement, 
    "ProblemConstraints" => \$constraints,
    "InputFormat" => \$inputformat, 
    "OutputFormat" => \$outputformat 
    );


sub note($) {
    $import_log .= $_[0];
}


sub warning($) 
{
    my $m = "Warning: ".shift;
    $import_log .= $m;
}


sub error($) 
{
    my $m = "Error: ".shift;
    $import_log .= $m;
    die $m;
}


sub start_element
{
    my ($stream, $el, %atts) = @_;
    
    $$stream .= "<$el";
    foreach my $name (keys %atts)
    {
        $$stream .= " $name=\"$atts{$name}\"";;
    }
    $$stream .= ">";
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
        start_element($stml, $el, %atts); 
        return; 
    }        
        
    if (defined $stml_tags{$el}) { 
        $stml = $stml_tags{$el}; 
    }

    
    if ($el eq 'Problem')
    {
        defined $atts{'title'}
            or error "Problem.title not specified\n";

        defined $atts{'lang'}
            or error "Problem.lang not specified\n";

        defined $atts{'tlimit'}
            or error "Problem.tlimit not specified\n";

        defined $atts{'inputFile'}
            or error "Problem.inputFile not specified\n";

        defined $atts{'outputFile'}
            or error "Problem.outputFile not specified\n";

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
                    

sub parse_problem_content
{
    my ($p, $el, %atts) = @_;

    if ($el eq "Picture")
    {
        defined $atts{'src'}
            or error "Picture.src not specified\n";

        defined $atts{'name'}
            or error "Picture.name not specified\n";

        my @p = split(/\./, $atts{'src'}); my $ext = $p[-1];
        error "Invalid image extension\n" if ($ext eq '') ;
        
        my $member = $zip->memberNamed($atts{'src'}) 
            or error "Invalid picture reference: '$atts{'src'}'\n";

        %picture = (
            'id' => new_id,
            'src' => read_member($member),
            'path' => $atts{'src'},
            'name' => $atts{'name'},
            'ext' => $ext
        )
    }

    if ($el eq 'Solution')
    {
        defined $atts{'src'}
            or error "Solution.src not specified\n";

        defined $atts{'name'}
            or error "Solution.name not specified\n";

        my $id = new_id;
        set_object_id($atts{'name'}, $id);

        my $member = $zip->memberNamed($atts{'src'}) 
            or error "Invalid solution reference: '$atts{'src'}'\n";

        %solution = (   
            'id' => $id,
            'src' => read_member($member),
            'path' => $atts{'src'},
            'de_code' => $atts{'de_code'},
            'checkup' => $atts{'checkup'}       
        )
    }

    if ($el eq 'Checker')
    {
        defined $atts{'src'}
            or error "Checker.src not specified\n";

        my $member = $zip->memberNamed($atts{'src'}) 
            or error "Invalid checker reference: '$atts{'src'}'\n";
            
        %checker = (    
            'src' => read_member($member),
            'path' => $atts{'src'},
            'de_code' => $atts{'de_code'}
        )
    }

    if ($el eq 'Generator')
    {
        defined $atts{'src'}
            or error "Generator.src not specified\n";

        defined $atts{'name'}
            or error "Generator.name not specified\n";
        
        my $id = new_id;
        set_object_id($atts{'name'}, $id);

        my $member = $zip->memberNamed($atts{'src'}) 
            or error "Invalid generator reference: '$atts{'src'}'\n";

        %generator = (  
            'id' => $id,
            'src' => read_member($member),
            'path' => $atts{'src'},
            'de_code' => $atts{'de_code'}
        )
    }

    if ($el eq 'Test')
    {
        defined $atts{'rank'}
            or error "Test.rank not specified\n";

        if (defined $test_rank_array{$atts{'rank'}}) {            
            error "Duplicate test $atts{'rank'}\n";
        }
        
        %test = (
            'rank' => $atts{'rank'},
            'in' => 1
        );

        $test_rank_array{$atts{'rank'}} = 1;
    }   

    if ($el eq 'TestRange')
    {
        defined $atts{'from'}
            or error "TestRange.from not specified\n";

        defined $atts{'to'}
            or error "TestRange.to not specified\n";
              
        %test_range = (
            'from' => $atts{'from'},
            'to' => $atts{'to'},
            'in' => 1
        );

        foreach ($atts{'from'}..$atts{'to'})
        {
            if (defined $test_rank_array{$_}) {            
                error "Duplicate test $_\n";
            }
            $test_rank_array{$_} = 1;
        }
    }   


    if ($el eq 'In' && $test{in})
    {       
        if (defined $atts{'src'}) 
        {
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
            error "Test input file not specified\n";
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
            error "Test output file not specified\n";
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
            error "Test input file not specified\n";
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
            error "Test output file not specified\n";
        }
    }       


    if ($el eq 'Sample')
    {
        defined $atts{'rank'}
            or error "Sample.rank not specified\n";

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


sub apply_test_rank
{
    my ($v, $rank) = @_;
    $v =~ s/%n/$rank/g;
    $v =~ s/%0n/sprintf("%02d", $rank)/eg;

    $v;
}


sub insert_problem_content
{
    my ($p, $el) = @_;

    if ($el eq 'Generator')
    {
        my $c = $dbh->prepare(qq~INSERT INTO problem_sources
        (id, problem_id, de_id, src, fname, stype) VALUES (?,?,?,?,?,?)~);
        
        $c->bind_param(1, $generator{'id'});
        $c->bind_param(2, $pid);
        $c->bind_param(3, get_de_id($generator{'de_code'}, $generator{'path'}));
        $c->bind_param(4, $generator{'src'}, { ora_type => 113 });
        $c->bind_param(5, $generator{'path'});
        $c->bind_param(6, $cats::generator);
        $c->execute;

        note "Generator '$generator{'path'}' added\n";

        %generator = ();
    }

    if ($el eq 'Solution')
    {
        my $c = $dbh->prepare(qq~INSERT INTO problem_sources
        (id, problem_id, de_id, src, fname, stype) VALUES (?,?,?,?,?,?)~);
        
        $c->bind_param(1, $solution{'id'}); 
        $c->bind_param(2, $pid);
        $c->bind_param(3, get_de_id($solution{'de_code'}, $solution{'path'}));
        $c->bind_param(4, $solution{'src'}, { ora_type => 113 });
        $c->bind_param(5, $solution{'path'});
        $c->bind_param(6, (defined $solution{'checkup'} && $solution{'checkup'} == 1) ? $cats::adv_solution : $cats::solution);
        $c->execute;

        note "Solution '$solution{'path'}' added\n";

        %solution = ();
    }

    if ($el eq 'Checker')
    {
        my $c = $dbh->prepare(qq~INSERT INTO problem_sources
        (id, problem_id, de_id, src, fname, stype) VALUES (?,?,?,?,?,?)~);
    
        $c->bind_param(1, new_id);
        $c->bind_param(2, $pid);
        $c->bind_param(3, get_de_id($checker{'de_code'}, $checker{'path'}));
        $c->bind_param(4, $checker{'src'}, { ora_type => 113 });
        $c->bind_param(5, $checker{'path'});
        $c->bind_param(6, $cats::checker);
        $c->execute;

        note "Checker '$checker{'path'}' added\n";

        %checker = ();
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
        my $c = $dbh->prepare(qq~INSERT INTO tests (problem_id, rank, generator_id, param, std_solution_id, in_file, out_file)
            VALUES (?,?,?,?,?,?,?)~);
            
        $c->bind_param(1, $pid);
        $c->bind_param(2, $test{'rank'});
        $c->bind_param(3, $test{'generator_id'});
        $c->bind_param(4, $test{'param'});
        $c->bind_param(5, $test{'std_solution_id'} );
        $c->bind_param(6, $test{'in_file'}, { ora_type => 113 });
        $c->bind_param(7, $test{'out_file'}, { ora_type => 113 });
        $c->execute;

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
            
            my $c = $dbh->prepare(qq~INSERT INTO tests (problem_id, rank, generator_id, param, std_solution_id, in_file, out_file)
                VALUES (?,?,?,?,?,?,?)~);
               
            $c->bind_param(1, $pid);
            $c->bind_param(2, $rank);
            $c->bind_param(3, get_object_id($gen));
            $c->bind_param(4, $param);
            $c->bind_param(5, get_object_id($sol));
            $c->bind_param(6, $in_file, { ora_type => 113 });
            $c->bind_param(7, $out_file, { ora_type => 113 });
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
        my $c = $dbh->prepare(qq~INSERT INTO samples (problem_id, rank, in_file, out_file)
            VALUES (?,?,?,?)~);
            
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

        $zip_archive = "";
        
        my $buffer;
        while (sysread(FILE, $buffer, 4096)) {
            $zip_archive .= $buffer;
        }
    
        close FILE;    
                    
        $zip = Archive::Zip->new();
        error "read '$fname' failed\n" unless ($zip->read($fname) == AZ_OK);

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
        note "Import failed\n";
    }

    return ($res, $import_log);
}

1;


