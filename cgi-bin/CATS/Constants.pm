package cats;

$anonymous_login = 'anonymous';

@templates = (
    { id => "std", path => "./../templates/std" },
    { id => "alt", path => "./../templates/alt" }
);

@langs = qw(ru en);

# Values for accounts.srole.
$srole_root = 0;
$srole_user = 1;
$srole_contests_creator = 2;

# Values problem_sources.stype.
$generator = 0;
$solution = 1;
$checker = 2;
$adv_solution = 3;
$generator_module = 4;
$solution_module = 5;
$checker_module = 6;
$testlib_checker = 7;
$partial_checker = 8;
$validator = 9;
$validator_module = 10;

%source_module_names = (
    $generator => 'generator',
    $solution => 'solution',
    $checker => 'checker (deprecated)',
    $adv_solution => 'solution (autorun)',
    $generator_module => 'generator module',
    $solution_module => 'solution module',
    $checker_module => 'checker module',
    $testlib_checker => 'checker',
    $partial_checker => 'partial checker',
    $validator => 'validator',
    $validator_module => 'validator module'
);

# Map source types to module types.
%source_modules = (
    $generator => $generator_module,
    $solution => $solution_module,
    $adv_solution => $solution_module,
    $checker => $checker_module,
    $testlib_checker => $checker_module,
    $partial_checker => $checker_module,
    $validator => $validator_module
);

# Values for reqs.state.
$st_not_processed = 0;
$st_unhandled_error = 1;
$st_install_processing = 2;
$st_testing = 3;

# This value should not actuall exist in the database.
# Values greater than this indicate that judge has finished processing.
$request_processed = 9;

$st_accepted = 10;
$st_wrong_answer = 11;
$st_presentation_error = 12;
$st_time_limit_exceeded = 13;
$st_runtime_error = 14;
$st_compilation_error = 15;
$st_security_violation = 16;
$st_memory_limit_exceeded = 17;
$st_ignore_submit = 18;
$st_idleness_limit_exceeded = 19;

# Values for contest_problems.status.
$problem_st_ready     = 0;
$problem_st_suspended = 1;
$problem_st_disabled  = 2;
$problem_st_hidden    = 3;

# Values for problems.run_method.
$rm_default = 0;
$rm_interactive = 1;

$penalty = 20;

@problem_codes = ('A'..'Z', '1'..'9');
sub is_good_problem_code { $_[0] =~ /^[A-Z1-9]$/ }

# Length of input file prefix displayed to user.
$infile_cut = 30;

1;
