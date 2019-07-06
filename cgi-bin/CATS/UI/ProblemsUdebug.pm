package CATS::UI::ProblemsUdebug;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::ListView;
use CATS::Messages qw(res_str);
use CATS::Output qw(init_template url_f);

# API for https://www.udebug.com/CATS
sub problems_udebug_frame {
    my ($p) = @_;
    my $t = init_template($p, 'problems_udebug');
    my $lv = CATS::ListView->new(web => $p, name => 'problems_udebug');

    $lv->define_columns(url_f('problems'), 0, 0, [
        { caption => res_str(602), order_by => 'P.id', width => '30%' },
    ]);

    my $c = $dbh->prepare(q~
        SELECT
            CP.id AS cpid, P.id AS pid, CP.code, P.title, P.lang, C.title AS contest_title,
            SUBSTRING(P.explanation FROM 1 FOR 1) AS has_explanation,
            CP.status, P.upload_date
        FROM contest_problems CP
            INNER JOIN problems P ON CP.problem_id = P.id
            INNER JOIN contests C ON CP.contest_id = C.id
        WHERE
            C.is_official = 1 AND C.show_packages = 1 AND
            CURRENT_TIMESTAMP > C.finish_date AND (C.is_hidden = 0 OR C.is_hidden IS NULL) AND
            CP.status < ? AND P.lang STARTS WITH 'en' ~ . $lv->order_by);
    $c->execute($cats::problem_st_hidden);

    my $sol_sth = $dbh->prepare(q~
        SELECT PSL.fname, PSL.src, DE.code
        FROM problem_sources PS
        INNER JOIN problem_sources_local PSL ON PSL.id = PS.id
        INNER JOIN default_de DE ON DE.id = PSL.de_id
        WHERE PS.problem_id = ? AND PSL.stype = ?~);

    my $fetch_record = sub {
        my $r = $_[0]->fetchrow_hashref or return ();
        $sol_sth->execute($r->{pid}, $cats::solution);
        my $sols = $sol_sth->fetchall_arrayref({});
        return (
            href_view_problem => CATS::StaticPages::url_static('problem_text', cpid => $r->{cpid}),
            href_explanation => $r->{has_explanation} ?
                url_f('problem_text', cpid => $r->{cpid}, explain => 1) : '',
            href_download => url_function('problem_download', pid => $r->{pid}),
            cpid => $r->{cpid},
            pid => $r->{pid},
            code => $r->{code},
            title => $r->{title},
            contest_title => $r->{contest_title},
            lang => $r->{lang},
            status_text => CATS::Messages::problem_status_names()->{$r->{status}},
            upload_date_iso => date_to_iso($r->{upload_date}),
            solutions => $sols,
        );
    };

    $lv->attach(url_f('problems_udebug'), $fetch_record, $c);
    $c->finish;
}

1;
