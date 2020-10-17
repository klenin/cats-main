package CATS::UI::ViewSource;

use strict;
use warnings;

use Algorithm::Diff;
use Encode;

use CATS::DB;
use CATS::DevEnv;
use CATS::Globals qw($cid $contest $is_jury $user);
use CATS::Output qw(init_template url_f url_f_cid);
use CATS::Job;
use CATS::JudgeDB;
use CATS::Messages qw(msg);
use CATS::RankTable::Cache;
use CATS::ReqDetails qw(
    get_sources_info
    sources_info_param
    source_links
);
use CATS::Request;
use CATS::Settings qw($settings);
use CATS::Similarity;
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

    my $both_jury = 2 == grep $_->{is_jury}, @$si;
    if ($p->{reject_both} && $both_jury) {
        my %remove_cache;
        for my $r (@$si) {
            CATS::Job::cancel_all($r->{req_id});
            my %update = (
                failed_test => undef, state => $cats::st_manually_rejected,
                points => 0, tag => Encode::decode_utf8($p->{reject_both_message}),
            );
            CATS::Request::enforce_state($r->{req_id}, \%update);
            $remove_cache{$r->{contest_id}} = 1 unless $r->{is_hidden};
            $r->{$_} = $update{$_} for keys %update;
            CATS::ReqDetails::update_verdict($r);
        }
        $dbh->commit;
        CATS::RankTable::Cache::remove($_) for keys %remove_cache;
    }
    if ($both_jury) {
        my %ml = (max_lines => 20000);
        my %scores = (
            basic => CATS::Similarity::similarity_score_2(@$si, \%ml),
            collapse_idents =>
                CATS::Similarity::similarity_score_2(@$si, { collapse_idents => 1, %ml }),
        );
        $_ = sprintf '%.1f%%', 100 * $_ for values %scores;
        $t->param(similarity => \%scores);
    }

    for my $info (@$si) {
        $info->{lines} = [ split "\n", $info->{src} ];
        s/\s*$// for @{$info->{lines}};
        if ($p->{ignore_ws}) {
            s/^\s*// for @{$info->{lines}};
        }
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

    $t->param(diff_lines => \@diff, similar => $p->{similar} && $both_jury);
}

sub view_source_frame {
    my ($p) = @_;
    my $t = init_template($p, 'view_source.html.tt');
    $p->{rid} or return;
    my $sources_info = get_sources_info($p, request_id => $p->{rid}, get_source => 1, encode_source => 1);
    $sources_info or return;

    $p->{problem_id} = $sources_info->{problem_id};

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
        if ($p->{de_id} && ($p->{de_id} eq 'by_extension' || $p->{de_id} != $sources_info->{de_id})) {
            my $file = $p->{source};
            my $did = prepare_de($p, $file ? $file->remote_file_name : '', $sources_info->{cp_id});
            if ($did) {
                $u->{de_id} = $did;
                $de_bitmap = [ (CATS::DevEnv->new(CATS::JudgeDB::get_DEs()))->bitmap_by_ids($u->{de_id}) ];
            }
        }
        if ($u) {
            CATS::Request::update_source($sources_info->{req_id}, $u, $de_bitmap);
        }
        if ($p->{replace_and_submit}) {
            CATS::Request::retest($sources_info->{req_id});
            CATS::RankTable::Cache::remove($sources_info->{contest_id}) unless $sources_info->{is_hidden};
        }
        if ($u || $p->{replace_and_submit}) {
            $dbh->commit;
            $sources_info = get_sources_info($p,
                request_id => $p->{rid}, get_source => 1, encode_source => 1);
        }
    }
    else {
        msg(1014, $sources_info->{submit_time}) if $p->{submitted};
    }
    source_links($p, $sources_info);
    sources_info_param([ $sources_info ]);
    @{$sources_info->{elements}} <= 1 or return msg(1155);
    $sources_info->{href_print} = url_f('print_source', rid => $p->{rid}, notime => 1);
    CATS::ReqDetails::prepare_sources($p, $sources_info);
    
    if (
        $sources_info->{is_jury} || $sources_info->{status} != $cats::problem_st_disabled &&
        !CATS::Problem::Submit::user_is_banned($p->{problem_id}) && CATS::Problem::Submit::can_submit
    ) {
        $t->param(prepare_de_list(), de_selected => $sources_info->{de_id}, can_submit => 1);
    }
    $t->param(
        source_width => $settings->{source_width} // 90,
        href_action => url_f_cid('view_source', rid => $p->{rid}, cid => $sources_info->{contest_id}),
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
    my $ext = lc($1 || 'unknown');
    if ($p->{hash}) {
        $p->headers('Access-Control-Allow-Origin' => '*');
    }
    $p->print_file(
        ($ext eq 'zip' ?
            (content_type => 'application/zip') :
            (content_type => 'text/plain', charset => 'UTF-8')),
        file_name => "$si->{req_id}.$ext",
        content => $ext eq 'zip' ? $si->{src} : Encode::encode_utf8($si->{src}));
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
