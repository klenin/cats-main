package CATS::UI::ViewSource;

use strict;
use warnings;

use Algorithm::Diff;
use Encode;

use CATS::DB;
use CATS::DevEnv;
use CATS::Globals qw($cid $contest $is_jury $user);
use CATS::Output qw(init_template url_f);
use CATS::JudgeDB;
use CATS::Messages qw(msg);
use CATS::ReqDetails qw(
    get_compilation_error
    get_contest_info
    get_log_dump
    get_sources_info
    sources_info_param
    source_links);
use CATS::Request;
use CATS::Settings qw($settings);
use CATS::Problem::Submit qw(prepare_de prepare_de_list);

sub diff_runs_frame {
    my ($p) = @_;
    my $t = init_template($p, 'diff_runs.html.tt');
    $p->{r1} && $p->{r2} or return;

    my $si = get_sources_info($p,
        request_id => [ $p->{r1}, $p->{r2} ], get_source => 1, encode_source => 1) or return;
    @$si == 2 or return;

    source_links($p, $_) for @$si;
    sources_info_param($si);

    return msg(1155) if grep @{$_->{elements}} > 1, @$si;

    for my $info (@$si) {
        $info->{lines} = [ split "\n", $info->{src} ];
        s/\s*$// for @{$info->{lines}};
    }

    my @diff;

    my $SL = sub { $si->[$_[0]]->{lines}->[$_[1]] || '' };

    my $match = sub { push @diff, { class => 'diff_both', line => $SL->(0, $_[0]) }; };
    my $only_a = sub { push @diff, { class => 'diff_only_a', line => $SL->(0, $_[0]) }; };
    my $only_b = sub { push @diff, { class => 'diff_only_b', line => $SL->(1, $_[1]) }; };

    Algorithm::Diff::traverse_sequences(
        $si->[0]->{lines},
        $si->[1]->{lines},
        {
            MATCH     => $match,  # callback on identical lines
            DISCARD_A => $only_a, # callback on A-only
            DISCARD_B => $only_b, # callback on B-only
        }
    );

    $t->param(diff_lines => \@diff);
}

sub view_source_frame {
    my ($p) = @_;
    my $t = init_template($p, 'view_source.html.tt');
    $p->{rid} or return;
    my $sources_info = get_sources_info($p, request_id => $p->{rid}, get_source => 1, encode_source => 1);
    $sources_info or return;

    $p->{problem_id} = $dbh->selectrow_array(q~
            SELECT problem_id FROM reqs WHERE id = ?~,
            undef, $p->{rid});

    if ($p->{submit}) {
        my ($rid) = CATS::Problem::Submit::problems_submit($p);
        $rid and return $p->redirect(url_f 'view_source', rid => $rid, submitted => 1);
    }
    elsif ($sources_info->{is_jury} && $p->{replace}) {
        my $u;
        my $src = $p->{source} ? $p->{source}->content // die : $p->{source_text};
        if (defined $src && $src ne '') {
            $u->{src} = $src;
            $u->{hash} = CATS::Utils::source_hash($src);
        }
        my $de_bitmap;
        if ($p->{de_id} && $p->{de_id} != $sources_info->{de_id}) {
            my $cpid = $dbh->selectrow_array(q~
                SELECT CP.id
                FROM contest_problems CP
                INNER JOIN problems P ON P.id = CP.problem_id
                WHERE CP.contest_id = ? AND CP.problem_id = ?~, undef,
                $cid, $p->{problem_id}) or return msg(1012);
            my $file = $p->{source};
            my $did = prepare_de($p, $file ? $file->remote_file_name : '', $cpid);
            if ($did) {
                $u->{de_id} = $did;
                $de_bitmap = [ (CATS::DevEnv->new(CATS::JudgeDB::get_DEs()))->bitmap_by_ids($u->{de_id}) ];
            }
        }
        if ($u) {
            CATS::Request::update_source($sources_info->{req_id}, $u, $de_bitmap);
            $dbh->commit;
            $sources_info = get_sources_info($p,
                request_id => $p->{rid}, get_source => 1, encode_source => 1);
        }
    }
    else {
        msg(1014) if $p->{submitted};
    }
    source_links($p, $sources_info);
    sources_info_param([ $sources_info ]);
    @{$sources_info->{elements}} <= 1 or return msg(1155);
    $sources_info->{href_print} = url_f('print_source', rid => $p->{rid}, notime => 1);

    if ($sources_info->{file_name} =~ m/\.zip$/) {
        $sources_info->{src} = sprintf 'ZIP, %d bytes', length ($sources_info->{src});
    }
    if (my $r = $sources_info->{err_regexp}) {
        my (undef, undef, $file_name) = CATS::Utils::split_fname($sources_info->{file_name});
        CATS::Utils::sanitize_file_name($file_name);
        $file_name =~ s/([^a-zA-Z0-9_])/\\$1/g;
        for (split ' ', $r) {
            s/~FILE~/$file_name/;
            s/~LINE~/(\\d+)/;
            s/~POS~/\\d+/;
            push @{$sources_info->{err_regexp_js}}, "/$_/";
        }
    }
    $sources_info->{syntax} = $p->{syntax} if $p->{syntax};
    $sources_info->{src_lines} = [ map {}, split("\n", $sources_info->{src}) ];
    my $st = $sources_info->{state};
    if ($st == $cats::st_compilation_error || $st == $cats::st_lint_error) {
        my $logs = get_log_dump({ req_id => $sources_info->{req_id} });
        $sources_info->{compiler_output} = get_compilation_error($logs, $st)
    }

    my $can_submit = CATS::Problem::Submit::can_submit;
    
    if ($sources_info->{is_jury} || $can_submit) {
        $t->param(prepare_de_list(), de_selected => $sources_info->{de_id});
    }
    $t->param(
        source_width => $settings->{source_width} // 90,
        can_submit => $can_submit,
        href_action => url_f('view_source', rid => $p->{rid}),
    );
}

sub download_source_frame {
    my ($p) = @_;
    $p->{rid} or return;
    my $si = get_sources_info($p, request_id => $p->{rid}, get_source => 1, encode_source => 1);

    unless ($si) {
        init_template($p, 'view_source.html.tt');
        return;
    }

    $si->{file_name} =~ m/\.([^.]+)$/;
    my $ext = $1 || 'unknown';
    $p->print_file(
        ($ext eq 'zip' ?
            (content_type => 'application/zip') :
            (content_type => 'text/plain', charset => 'UTF-8')),
        file_name => "$si->{req_id}.$ext",
        content => Encode::encode_utf8($si->{src}));
}

sub print_source_frame {
    my ($p) = @_;
    my $t = init_template($p, 'print_source.html.tt');
    $p->{rid} or return;
    my $sources_info = get_sources_info($p, request_id => $p->{rid}, get_source => 1, encode_source => 1);
    $sources_info or return;
    $sources_info->{syntax} = $p->{syntax} if $p->{syntax};
    $t->param(sources_info => $sources_info);
}

1;
