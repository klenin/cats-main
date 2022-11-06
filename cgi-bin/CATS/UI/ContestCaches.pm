package CATS::UI::ContestCaches;

use strict;
use warnings;

use CATS::Contest::Utils;
use CATS::DB;
use CATS::Globals qw($cid $is_root $t);
use CATS::ListView;
use CATS::Messages qw(res_str);
use CATS::Output qw(init_template url_f);
use CATS::RankTable::Cache;
use CATS::StaticPages;
use CATS::Utils;

sub _clear_text_cache {
    CATS::StaticPages::invalidate_problem_text(cid => $cid, all => 1);
}

sub _clear_rank_cache {
    CATS::RankTable::Cache::remove($cid);
}

sub _name_size { [ map { n => $_, s => CATS::Utils::group_digits(-s $_) }, @_ ] }

sub _text_cache_files {
    _name_size glob CATS::StaticPages::full_name_glob('problem_text', @_);
}

sub contest_caches_frame {
    my ($p) = @_;

    init_template($p, 'contest_caches.html.tt');
    $is_root or return;

    _clear_text_cache($p) if $p->{clear_text_cache};
    _clear_rank_cache($p) if $p->{clear_rank_cache};

    my $problems = $dbh->selectall_arrayref(q~
        SELECT P.id, P.title, CP.code, CP.id AS cpid
        FROM contest_problems CP INNER JOIN problems P ON P.id = CP.problem_id
        WHERE CP.contest_id = ?
        ORDER BY CP.code~, { Slice => {} },
        $cid
    );

    $_->{caches} = _text_cache_files(cpid => $_->{cpid}) for @$problems;
    $t->param(
        text_caches => _text_cache_files(cid => $cid),
        problems => $problems,
        rank_caches => _name_size(CATS::RankTable::Cache::files($cid)),
        form_action => url_f('contest_caches'),
    );
    CATS::Contest::Utils::contest_submenu('contest_caches');
}

1;
