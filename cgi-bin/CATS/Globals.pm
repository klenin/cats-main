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
our $max_fetch_row_count = 1000;

our $default_de_tag = 7;

our $de_code_answer_text = 3;
our $de_code_quiz = 6;

our $contact_phone = 901;
our $contact_email = 902;

our $relation = { sees_reqs => 1, is_member_of => 2, upsolves_for => 3 };
our $relation_to_name = { reverse %$relation };

our $jobs;

our $binary_exts;

BEGIN {
    my $name_to_type = {
        submission => $cats::job_type_submission,
        snippets => $cats::job_type_generate_snippets,
        install => $cats::job_type_initialize_problem,
        submission_part => $cats::job_type_submission_part,
        update_self => $cats::job_type_update_self,
        manual_verdict => $cats::job_type_manual_verdict,
        run_command => $cats::job_type_run_command,
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

    my $ext_to_mime = {
        aac  => 'audio/aac',
        avi  => 'video/x-msvideo',
        bin  => 'application/octet-stream',
        bmp  => 'image/bmp',
        doc  => 'application/msword',
        docx => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        epub => 'application/epub+zip',
        gif  => 'image/gif',
        gz   => 'application/gzip',
        jpeg => 'image/jpeg',
        jpg  => 'image/jpeg',
        mp3  => 'audio/mpeg',
        mp4  => 'video/mp4',
        mpeg => 'video/mpeg',
        odp  => 'application/vnd.oasis.opendocument.presentation',
        ods  => 'application/vnd.oasis.opendocument.spreadsheet',
        odt  => 'application/vnd.oasis.opendocument.text',
        oga  => 'audio/ogg',
        ogv  => 'video/ogg',
        ogx  => 'application/ogg',
        opus => 'audio/opus',
        png  => 'image/png',
        pdf  => 'application/pdf',
        ppt  => 'application/vnd.ms-powerpoint',
        pptx => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        rar  => 'application/vnd.rar',
        rtf  => 'application/rtf',
        tif  => 'image/tiff',
        tiff => 'image/tiff',
        wav  => 'audio/wav',
        weba => 'audio/webm',
        webm => 'video/webm',
        webp => 'image/webp',
        xls  => 'application/vnd.ms-excel',
        xlsx => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        zip  => 'application/zip',
        '7z' => 'application/x-7z-compressed',
    };
    $binary_exts = {
        ext_to_mime => $ext_to_mime,
        re => join '|', sort keys %$ext_to_mime,
    };
};

1;
