package CATS::RunDetails;

use strict;
use warnings;

BEGIN
{
    no strict;
    use Exporter;
    @ISA = qw(Exporter);
    @EXPORT = qw(
        source_encodings
        source_links
    );
}

use CGI qw(param url_param);
use CATS::DB;
use CATS::Utils qw(url_function);
use CATS::Misc qw($sid $t url_f);

sub get_judge_name
{
    my ($judge_id) = @_ or return;
    scalar $dbh->selectrow_array(qq~
      SELECT nick FROM judges WHERE id = ?~, undef,
      $judge_id);
}


sub source_encodings { {'UTF-8' => 1, 'WINDOWS-1251' => 1, 'KOI8-R' => 1, 'CP866' => 1, 'UCS-2LE' => 1} }


sub source_links
{
    my ($si, $is_jury) = @_;
    my ($current_link) = url_param('f') || '';

    $si->{href_contest} =
        url_function('problems', cid => $si->{contest_id}, sid => $sid);
    $si->{href_problem} =
        url_function('problem_text', cpid => $si->{cp_id}, cid => $si->{contest_id}, sid => $sid);
    for (qw/run_details view_source run_log download_source/) {
        $si->{"href_$_"} = url_f($_, rid => $si->{req_id});
        $si->{"href_class_$_"} = $_ eq $current_link ? 'current_link' : '';
    }
    $si->{is_jury} = $is_jury;
    $t->param(is_jury => $is_jury);
    if ($is_jury && $si->{judge_id}) {
        $si->{judge_name} = get_judge_name($si->{judge_id});
    }
    my $se = param('src_enc') || param('comment_enc') || 'WINDOWS-1251';
    $t->param(source_encodings =>
        [ map {{ enc => $_, selected => $_ eq $se }} sort keys %{source_encodings()} ]);
}

1;
