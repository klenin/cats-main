package CATS::Globals;

use strict;
use warnings;

use CATS::Constants;

use Exporter qw(import);

# $cid = $contest->{id}
# $is_jury = $user->{is_jury}
# $is_root = $user->privs->{is_root}
# $uid = $user->id
our @EXPORT_OK = qw(
    $cid $contest $is_jury $is_root $sid $t $uid $user
);

our (
    $cid, $contest, $is_jury, $is_root, $t, $sid, $uid, $user
);

# Optimization: limit datasets by both maximum row count and maximum visible pages.
sub max_fetch_row_count() { 1000 }

our $default_de_tag = 7;

our $answer_text_de_code = 3;

our $contact_phone = 901;
our $contact_email = 902;

our $relation = { sees_reqs => 1, is_member_of => 2, upsolves_for => 3 };
our $relation_to_name = { reverse %$relation };

our $jobs;

BEGIN {
    my $name_to_type = {
        submission => $cats::job_type_submission,
        snippets => $cats::job_type_generate_snippets,
        install => $cats::job_type_initialize_problem,
        submission_part => $cats::job_type_submission_part,
        update_self => $cats::job_type_update_self,
    };
    my $name_to_state = {
        waiting => $cats::job_st_waiting,
        running => $cats::job_st_in_progress,
        finished => $cats::job_st_finished,
        failed => $cats::job_st_failed,
        waiting_for_verdict => $cats::job_st_waiting_for_verdict,
        canceled => $cats::job_st_canceled,

    };

    $jobs = {
        name_to_type => $name_to_type,
        name_to_state => $name_to_state,
        type_to_name => { reverse %$name_to_type },
        state_to_name => { reverse %$name_to_state },
    };
};

1;
