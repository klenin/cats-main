package CATS::Verdicts;

use strict;
use warnings;

use CATS::Constants;

our $name_to_state = {
    NP => $cats::st_not_processed,
    UH => $cats::st_unhandled_error,
    P  => $cats::st_install_processing,
    T =>  $cats::st_testing,
    AW => $cats::st_awaiting_verification,
    OK => $cats::st_accepted,
    WA => $cats::st_wrong_answer,
    PE => $cats::st_presentation_error,
    TL => $cats::st_time_limit_exceeded,
    RE => $cats::st_runtime_error,
    CE => $cats::st_compilation_error,
    SV => $cats::st_security_violation,
    ML => $cats::st_memory_limit_exceeded,
    IS => $cats::st_ignore_submit,
    IL => $cats::st_idleness_limit_exceeded,
    MR => $cats::st_manually_rejected,
    WL => $cats::st_write_limit_exceeded,
};

our $state_to_name = { map { $name_to_state->{$_} => $_ } keys %$name_to_state };

1;
