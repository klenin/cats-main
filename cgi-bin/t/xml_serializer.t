use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 43;
use Test::Exception;

use lib $FindBin::Bin;
use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Contest::XmlSerializer;
use CATS::Contest;

use TestLogger;

my $s = CATS::Contest::XmlSerializer->new(logger => TestLogger->new);
my $c = CATS::Contest->new({
    closed => 0,
    ctype => 0,
    defreeze_date => '12.06.2018 12:58',
    finish_date => '12.06.2018 12:58',
    freeze_date => '12.06.2018 12:58',
    id => 1774,
    is_hidden => 1,
    is_official => 1,
    local_only => 1,
    max_reqs => 123,
    max_reqs_except => '',
    penalty => undef,
    rules => 1,
    run_all_tests => 1,
    server_time => '12.06.2018 18:05',
    short_descr => 'df',
    show_all_tests=> 1,
    show_checker_comment => 1,
    show_flags => 1,
    show_packages => 1,
    show_sites => 1,
    show_test_data=> 1,
    show_test_resources => 1,
    start_date => '12.06.2018 12:58',
    time_since_defreeze => 0.213666042,
    time_since_finish => 0.213666042,
    time_since_start => 0.213666042,
    title => 'sdf',
});

my $problem = {
    id => 777,
    tags => 'tag1,tag2',
    code => 'A',
    status => 5,
    testsets => undef,
    contest_id => 1488,
    problem_id => 322,
    max_points => undef,
    time_limit => 1,
    write_limit => undef,
    memory_limit => 64,
    points_testsets => undef,
};

my $expected = 
q~<?xml version="1.0"?>
<CATS-Contest>
  <Closed>0</Closed>
  <ContestType>normal</ContestType>
  <DefreezeDate>12.06.2018 12:58</DefreezeDate>
  <FinishDate>12.06.2018 12:58</FinishDate>
  <Id>1774</Id>
  <IsHidden>1</IsHidden>
  <IsOfficial>1</IsOfficial>
  <LocalOnly>1</LocalOnly>
  <MaxReqs>123</MaxReqs>
  <MaxReqsExcept></MaxReqsExcept>
  <Rules>school</Rules>
  <RunAllTests>1</RunAllTests>
  <ShortDescr>df</ShortDescr>
  <ShowAllTests>1</ShowAllTests>
  <ShowCheckerComment>1</ShowCheckerComment>
  <ShowFlags>1</ShowFlags>
  <ShowPackages>1</ShowPackages>
  <ShowSites>1</ShowSites>
  <ShowTestData>1</ShowTestData>
  <ShowTestResources>1</ShowTestResources>
  <StartDate>12.06.2018 12:58</StartDate>
  <Title>sdf</Title>
</CATS-Contest>~;

my $problem_expected =
q~<Problem>
  <Code>A</Code>
  <ContestId>1488</ContestId>
  <MemoryLimit>64</MemoryLimit>
  <ProblemId>322</ProblemId>
  <Status>hidden</Status>
  <Tags>tag1,tag2</Tags>
  <TimeLimit>1</TimeLimit>
</Problem>~;

sub cats_contest {
    join "\n",
        q~<?xml version="1.0"?>~,
        '<CATS-Contest>',
        @_,
        '</CATS-Contest>';
}

is $s->serialize($c), $s->serialize($c), 'purity check';
is $s->serialize($c), $expected, 'correctness 1';

is $s->serialize_problem($problem), $s->serialize_problem($problem), 'problem purity check';
is $s->serialize_problem($problem), $problem_expected, 'problem check 1';

my $contest = $s->parse_xml($expected);
$_ eq 'problems' ? undef : is $contest->{$_}, $c->{$_}, "$_ check" for keys %$contest;

$contest = $s->parse_xml(cats_contest("$problem_expected<Problem><Code>B</Code></Problem>"));
my $ps = $contest->{problems};

is scalar @$ps, 2, 'length check';
is $ps->[1]->{code}, 'B', 'code check 2';
is $ps->[0]->{$_}, $problem->{$_}, "$_ check" for keys %{$ps->[0]};

throws_ok { $s->parse_xml(cats_contest('<UnknownTag>123</Closed>')) } qr/Unknown tag/, 'unknown tag at the start';
throws_ok { $s->parse_xml(cats_contest('<Closed>123</UnknownTag>')) } qr/mismatched tag/, 'unknown tag at the end';
throws_ok { $s->parse_xml(cats_contest('<UnknownTag/>')) } qr/Unknown tag/, 'unknown void tag';
throws_ok { $s->parse_xml(cats_contest('<Closed>3</Closed>')) } qr/not bool/, 'not bool';
throws_ok { $s->parse_xml(cats_contest('<Id>Iamnotid</Id>')) } qr/not int/, 'not int';
throws_ok { $s->parse_xml(cats_contest('<Rules>advanced</Rules>')) } qr/not enum/, 'not enum or wrong enum value';
throws_ok { $s->parse_xml(cats_contest('<Closed>1<Rules>normal</Rules></Closed>')) } qr/must be inside/, 'wrong parent tag';
throws_ok { $s->parse_xml(q~<?xml version="1.0"?><CATS-Contest>~) } qr/no element found/, 'bad xml';
