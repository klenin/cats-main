use strict;
use warnings;

use File::Path 'remove_tree';
use Getopt::Long;

GetOptions(
    'debug=s@' => \(my $debug),
    help => \(my $help),
    'install=s@' => \(my $install = []),
    list => \(my $list),
    'path=s' => \(my $path = 'js/lib'),
    'temp=s' => \(my $temp = 'tmp_js'),
);

my @debug_opts = qw(preserve verbose very_verbose);
my %dbg;
for my $d (@$debug) {
    grep $_ eq $d, @debug_opts or die "Unknown debug option: $d";
    $dbg{$_} = 1;
}

if ($help || !@$install && !$list) {
    printf STDERR qq~CATS JS installer tool
Usage: $0 [--help]
    [--debug=%s]
    [--install=<library>|all]
    [--list]
    [--path=<destination path>, default is js/lib]
    [--temp=<temporary path>, default is tmp_js]
~, join '|', @debug_opts;
    exit;
}

my $modules = [
    {
        name => 'ace',
        url => 'https://github.com/ajaxorg/ace-builds/archive/v1.3.3.zip',
        src => 'ace-builds-1.3.3/src-min-noconflict',
        dest => 'ace',
    },
    {
        name => 'autocomplete',
        url => 'https://github.com/devbridge/jQuery-Autocomplete/archive/v1.4.9.zip',
        src => 'jQuery-Autocomplete-1.4.9/dist',
        dest => 'autocomplete',
    },
    {
        name => 'datepicker',
        url => 'https://github.com/fengyuanchen/datepicker/archive/v1.0.0.zip',
        src => 'datepicker-1.0.0/dist',
        dest => 'datepicker',
    },
    {
        name => 'flot',
        url => 'http://www.flotcharts.org/downloads/flot-0.8.3.zip',
        src => 'flot/jquery.flot.min.js',
    },
    {
        name => 'jquery',
        url => 'https://code.jquery.com/jquery-3.6.0.min.js',
        dest => 'jquery.min.js',
    },
    {
        name => 'mathjax',
        url => 'https://github.com/mathjax/MathJax/archive/2.7.1.zip',
        src => 'MathJax-2.7.1',
        dest => 'MathJax',
    },
    {
        name => 'survey',
        url => 'https://unpkg.com/survey-jquery@1.9.39/survey.jquery.js',
        dest => 'survey.jquery.js',
    },
    {
        name => 'hunspell_aff',
        url => 'https://github.com/LibreOffice/dictionaries/blob/master/ru_RU/ru_RU.aff',
    },
    {
        name => 'hunspell_dic',
        url => 'https://github.com/LibreOffice/dictionaries/raw/master/ru_RU/ru_RU.dic',
    },
];

if ($list) {
    for my $m (@$modules) {
        printf "%12s: %s\n", $m->{name}, $m->{url};
    }
}

$install = [ map $_->{name}, @$modules ] if grep $_ eq 'all', @$install;
$temp = '' if $temp =~ /^\.+$/;

if (@$install) {
    my %modules_index;
    $modules_index{$_->{name}} = $_ for @$modules;
    if (my @not_found = grep !$modules_index{$_}, @$install) {
        printf "Unknown modules: %s\n", join ', ', @not_found;
        exit 1;
    }
    -d $path or die sprintf "Destinathion path does not exist: %s", $path;
    {
        my $wget = `wget --version` or die "wget: $!";
        printf "wget: %s\n", $wget if $dbg{very_verbose};
        my $unzip = `unzip -v` or die "unzip: $!";
        printf "unzip: %s\n", $unzip if $dbg{very_verbose};
    }
    if ($temp) {
        mkdir $temp or die "mkdir: $!" if !-d $temp;
        chdir $temp;
    }
    for my $name (@$install) {
        printf "Installing: %s...%s", $name, $dbg{verbose} ? "\n" : '';
        my $m = $modules_index{$name};
        my $q = $dbg{verbose} ? '' : '-q';
        my ($filename) = ($m->{url} =~ /\/([a-zA-Z0-9_\-\.]+)$/) or die $m->{url};
        if (-e $filename) {
            printf "Already exists: %s\n", $filename if $dbg{verbose};
        }
        else {
            `wget $q $m->{url}`;
        }
        if ($filename =~ /\.zip$/) {
            `unzip -o $q $filename`;
        }
        my $src = $m->{src} || $filename;
        my $dest = $m->{dest} // '';
        printf "==> %s\n", $filename if $dbg{verbose};
        `mv $src ../$path/$dest`;
        print "ok\n";
    }
    if ($temp) {
        chdir '..';
        remove_tree $temp if !$dbg{preserve};
    }
}
