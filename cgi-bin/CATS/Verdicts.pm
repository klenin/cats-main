package CATS::Verdicts;

use strict;
use warnings;

use CATS::Constants;

our $name_to_state_sorted = [
    [ NP => $cats::st_not_processed ],
    [ UH => $cats::st_unhandled_error ],
    [ P  => $cats::st_install_processing ],
    [ T =>  $cats::st_testing ],
    [ AW => $cats::st_awaiting_verification ],
    [ OK => $cats::st_accepted ],
    [ WA => $cats::st_wrong_answer ],
    [ PE => $cats::st_presentation_error ],
    [ TL => $cats::st_time_limit_exceeded ],
    [ RE => $cats::st_runtime_error ],
    [ CE => $cats::st_compilation_error ],
    [ SV => $cats::st_security_violation ],
    [ ML => $cats::st_memory_limit_exceeded ],
    [ IS => $cats::st_ignore_submit ],
    [ IL => $cats::st_idleness_limit_exceeded ],
    [ MR => $cats::st_manually_rejected ],
    [ WL => $cats::st_write_limit_exceeded ],
    [ LI => $cats::st_lint_error ],
];

our $name_to_state = { map @$_, @$name_to_state_sorted };

our $state_to_name = { map { $_->[1] => $_->[0] } @$name_to_state_sorted };

# What other paricipants see during official contest.
our $hidden_verdicts_others = {
    NP => 'NP',
    UH => 'NP',
    P  => 'NP',
    T =>  'NP',
    AW => 'NP',
    OK => 'OK',
    WA => 'RJ',
    PE => 'RJ',
    TL => 'RJ',
    RE => 'RJ',
    CE => 'RJ',
    SV => 'RJ',
    ML => 'RJ',
    IS => 'RJ',
    IL => 'RJ',
    MR => 'RJ',
    WL => 'RJ',
    LI => 'RJ',
};

# What non-jury see during official contest.
our $hidden_verdicts_self = {
    UH => 'NP',
    P  => 'NP',
};

1;
