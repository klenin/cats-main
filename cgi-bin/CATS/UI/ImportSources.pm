package CATS::UI::ImportSources;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::Globals qw($is_jury $t $uid);
use CATS::ListView;
use CATS::Messages qw(res_str);
use CATS::Output qw(init_template url_f url_f_cid);
use CATS::References;

sub import_sources_frame {
    my ($p) = @_;
    init_template($p, 'import_sources');
    my $lv = CATS::ListView->new(web => $p, name => 'import_sources', url => url_f('import_sources'));
    $lv->default_sort(0)->define_columns([
        { caption => res_str(625), order_by => 'guid', width => '20%' },
        { caption => res_str(601), order_by => 'fname', width => '20%' },
        { caption => res_str(642), order_by => 'stype', width => '20%' },
        { caption => res_str(641), order_by => 'code', width => '20%' },
        { caption => res_str(643), order_by => 'ref_count', width => '10%' },
    ]);
    $lv->define_db_searches([ qw(PS.id guid stype code fname problem_id title contest_id) ]);
    $lv->default_searches([ qw(guid fname title) ]);
    $lv->define_enums({
        stype => { reverse %cats::source_module_names },
    });

    my $sth = $dbh->prepare(q~
        SELECT ps.id, psl.guid, psl.stype, de.code,
            (SELECT COUNT(*) FROM problem_sources_imported psi WHERE psl.guid = psi.guid) AS ref_count,
            psl.fname, ps.problem_id, p.title, p.contest_id,
            (SELECT CA.is_jury FROM contest_accounts CA
                WHERE CA.account_id = ? AND CA.contest_id = p.contest_id)
            FROM problem_sources ps
            INNER JOIN problem_sources_local psl ON psl.id = ps.id
            INNER JOIN default_de de ON de.id = psl.de_id
            INNER JOIN problems p ON p.id = ps.problem_id
            WHERE psl.guid IS NOT NULL ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($uid // 0, $lv->where_params);

    my $fetch_record = sub {
        my $f = $_[0]->fetchrow_hashref or return ();
        return (
            %$f,
            stype_name => $cats::source_module_names{$f->{stype}},
            href_problem => url_f_cid('problem_details', cid => $f->{contest_id}, pid => $f->{problem_id}),
            href_source => url_f('import_source_view', guid => $f->{guid}),
            href_download => url_f('download_import_source', psid => $f->{id}),
        );
    };

    $lv->attach($fetch_record, $sth);

    $t->param(submenu => [ CATS::References::menu('import_sources') ]) if $is_jury;
}

sub _jury_submenu {
    my ($is) = @_;
    my %c = (cid => $is->{contest_id}, pid => $is->{problem_id});
    (
        { href => url_f_cid('problem_details', %c), item => res_str(504) },
        { href => url_f_cid('problem_history_edit', %c, file => $is->{fname}, hb => '0'),
            item => res_str(572) },
    );
}

sub import_source_view_frame {
    my ($p) = @_;
    $p->{guid} or return;
    init_template($p, 'import_source_view');
    my $rows = $dbh->selectall_arrayref(q~
        SELECT
            PSL.guid, PSL.fname, PSL.src,
            D.syntax, PS.id AS psid, PS.problem_id, P.contest_id, CA.is_jury
        FROM problem_sources_local PSL
        INNER JOIN problem_sources PS ON PS.id = PSL.id
        INNER JOIN default_de D ON D.id = PSL.de_id
        INNER JOIN problems P ON P.id = PS.problem_id
        LEFT JOIN contest_accounts CA ON CA.contest_id = P.contest_id AND CA.account_id = ?
        WHERE PSL.guid = ?~, { Slice => {} },
        $uid, $p->{guid}) or return;
    my $is = $rows->[0];
    $t->param(
        import_source => $is,
        problem_title => $p->{guid},
        title_suffix => $p->{guid},
        submenu => [
            ($is->{is_jury} ? _jury_submenu($is) : ()),
            { href => url_f('download_import_source', psid => $is->{psid}), item => res_str(569) },
            { href => url_f('import_sources'), item => res_str(557) },
        ],
    );
}

sub download_frame {
    my ($p) = @_;
    $p->{psid} or return;
    # Source encoding may be arbitrary.
    $CATS::DB::db->disable_utf8;
    my @row = $dbh->selectrow_array(q~
        SELECT fname, src FROM problem_sources_local WHERE id = ? AND guid IS NOT NULL~, undef,
        $p->{psid});
    $CATS::DB::db->enable_utf8;
    @row or return;
    $p->print_file(
        content_type => 'text/plain',
        file_name => $row[0],
        content => Encode::encode_utf8($row[1]));
}

1;
