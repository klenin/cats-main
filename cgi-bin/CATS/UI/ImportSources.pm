package CATS::UI::ImportSources;

use strict;
use warnings;

use CATS::Web qw(param url_param);
use CATS::DB;
use CATS::Constants;
use CATS::Misc qw(
    $t $is_jury $is_root $is_team $sid $cid $uid $contest $is_virtual $settings
    init_template init_listview_template msg res_str url_f auto_ext
    order_by define_columns attach_listview references_menu);
use CATS::Utils qw(url_function);
use CATS::Web qw(redirect);

sub import_sources_frame
{
    init_listview_template('import_sources', 'import_sources', 'import_sources.html.tt');
    define_columns(url_f('import_sources'), 0, 0, [
        { caption => res_str(625), order_by => '2', width => '30%' },
        { caption => res_str(642), order_by => '3', width => '30%' },
        { caption => res_str(641), order_by => '4', width => '30%' },
        { caption => res_str(643), order_by => '5', width => '10%' },
    ]);

    my $c = $dbh->prepare(q~
        SELECT ps.id, ps.guid, ps.stype, de.code,
            (SELECT COUNT(*) FROM problem_sources_import psi WHERE ps.guid = psi.guid) AS ref_count,
            ps.fname, ps.problem_id, p.title, p.contest_id,
            (SELECT CA.is_jury FROM contest_accounts CA WHERE CA.account_id = ? AND CA.contest_id = p.contest_id)
            FROM problem_sources ps INNER JOIN default_de de ON de.id = ps.de_id
            INNER JOIN problems p ON p.id = ps.problem_id
            WHERE ps.guid IS NOT NULL ~.order_by);
    $c->execute($uid);

    my $fetch_record = sub {
        my $f = $_[0]->fetchrow_hashref or return ();
        return (
            %$f,
            stype_name => $cats::source_module_names{$f->{stype}},
            href_problems => url_function('problems', sid => $sid, cid => $f->{contest_id}),
            href_source => url_f('download_import_source', psid => $f->{id}),
        );
    };

    attach_listview(url_f('import_sources'), $fetch_record, $c);

    $t->param(submenu => [ references_menu('import_sources') ], is_jury => 1) if $is_jury;
}

sub download_frame
{
    my $psid = param('psid') or return;
    local $dbh->{ib_enable_utf8} = 0;
    my ($fname, $src) = $dbh->selectrow_array(qq~
        SELECT fname, src FROM problem_sources WHERE id = ? AND guid IS NOT NULL~, undef, $psid) or return;
    CATS::Web::content_type('text/plain');
    CATS::Web::headers('Content-Disposition' => "inline;filename=$fname");
    CATS::Web::print($src);
}

1;
