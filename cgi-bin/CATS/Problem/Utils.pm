package CATS::Problem::Utils;

use strict;
use warnings;

use CATS::Constants;

sub gen_group_text {
    my ($t) = @_;
    defined $t->{input} && !defined $t->{input_file_size} ? '' :
    $t->{gen_group} ? "$t->{gen_name} GROUP" :
    $t->{gen_name} ? "$t->{gen_name} $t->{param}" : '';
}

sub run_method_enum() {+{
    default => $cats::rm_default,
    interactive => $cats::rm_interactive,
    competitive => $cats::rm_competitive,
}}

1;
