package CATS::UI::Grades;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($cid $is_jury $t);
use CATS::Messages;
use CATS::Output qw(init_template url_f);
use CATS::Problem::Submit;
use CATS::User;

my %user_fields = map { $_ => $_ } qw(id login team_name);

sub _set_once {
    my ($value_ref, $new_value, $report, $name) = @_;
    if (defined $$value_ref) { push @$report, "Duplicate $name: $$value_ref and $new_value"; }
    else { $$value_ref = $new_value; }
}

sub grades_import_frame {
    my ($p) = @_;
    init_template($p, 'grades_import');
    $is_jury or return;
    my $problems = $dbh->selectall_arrayref(q~
        SELECT CP.code, P.id, P.title
        FROM problems P
        INNER JOIN contest_problems CP ON P.id = CP.problem_id
        WHERE CP.contest_id = ? AND CP.status NOT IN (?, ?)
        ORDER BY CP.code~, { Slice => {} },
        $cid, $cats::problem_st_ready, $cats::problem_st_nosubmit);
    my $contact_types = $dbh->selectall_hashref(q~
        SELECT id, name FROM contact_types~, 'name');
    my @report;

    $t->param(
        href_action => url_f('grades_import'), #title_suffix => res_str(564),
        problems => $problems,
        problem_id => $p->{problem_id},
        report => \@report,
        CATS::User::users_submenu($p),
        contact_types => $contact_types, user_fields => \%user_fields,
    );

    $p->{problem_id} && $p->{go} or return;

    my ($header, @lines) = split "\r\n", $p->{grades};
    my (@header_fields) = split "\t", $header;
    my ($key_idx, $points_idx, $source_idx);
    for (my $i = 0; $i < @header_fields; ++$i) {
        my $h = $header_fields[$i];
        if ($h eq 'points') { _set_once(\$points_idx, $i, \@report, 'points'); }
        elsif ($h eq 'source') { _set_once(\$source_idx, $i, \@report, 'source'); }
        elsif ($user_fields{$h} || $contact_types->{$h}) { _set_once(\$key_idx, $i, \@report, 'key'); }
        else { push @report, "Unknown column: $h"; }
    }
    defined $key_idx or push @report, 'Key must be defined';
    defined $points_idx || defined $source_idx
        or push @report, 'At least one of points or source must be defined';
    return if @report;

    my $key_field = $header_fields[$key_idx];
    my $users_find_sth = $user_fields{$key_field} ?
        $dbh->prepare(qq~
            SELECT A.id, A.team_name FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id AND CA.contest_id = $cid
            WHERE A.$key_field = ?~) :
        $dbh->prepare(qq~
            SELECT A.id, A.team_name FROM accounts A
            INNER JOIN contest_accounts CA ON CA.account_id = A.id AND CA.contest_id = $cid
            INNER JOIN contacts C
                ON C.account_id = A.id AND C.contact_type_id = $contact_types->{$key_field}->{id}
            WHERE C.handle = ?~);

    my $count = 0;

    for my $line (@lines) {
        my @cols = split "\t", $line;
        $users_find_sth->execute($cols[$key_idx]);
        my $users = $users_find_sth->fetchall_arrayref([]);
        if (@$users > 1) {
            push @report, "Ambiguous $key_field: $cols[$key_idx]";
            next;
        }
        if (!@$users) {
            push @report, "Unknown $key_field: $cols[$key_idx]";
            next;
        }

        my ($user_id, $user_name) = @{$users->[0]};
        $p->{source_text} = $source_idx ? $cols[$source_idx] : '';
        $p->{de_code} = $CATS::Globals::de_code_answer_text;
        $p->{submit_as_id} = $user_id;
        $p->{submit_points} = $cols[$points_idx] if $points_idx;

        my ($rid, $result) = $p->{apply_changes} ? CATS::Problem::Submit::problems_submit($p) : (1, {});
        push @report,
            "$user_name uid=$user_id pts=$p->{submit_points} " .
            ($rid ? 'ok' : 'error ' . (join ' | ', @{CATS::Messages::get()}, %$result));
        CATS::Messages::clear;
    }
}

1;
