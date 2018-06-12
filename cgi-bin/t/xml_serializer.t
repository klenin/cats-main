use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 2;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::Contest::XmlSerializer;
use CATS::Contest;

my $s = CATS::Contest::XmlSerializer->new();
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
</CATS-Contest>
~;

is $s->serialize($c), $s->serialize($c), "purity check";
is $s->serialize($c), $s->serialize($c), "correctness 1";
