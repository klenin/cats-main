package CATS::UI::RankTable;

use strict;
use warnings;

use Text::CSV;

use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $sid $t $uid);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::RankTable;
use CATS::RouteParser;

our @router_bool_params = qw(
    cache
    hide_ooc
    hide_virtual
    notime
    nostats
    points
    printable
    show_flags
    show_logins
    show_prizes
    show_regions
);

our @router_params = (
    #accounts => clist_of integer,
    filter => str,
    groups => clist_of integer,
    points_max => integer,
    points_min => integer,
    sites => clist_of integer,
    sort => ident,
);

sub rank_table {
    my ($p, $template_name) = @_;
    init_template($p, 'rank_table_content');
    $t->param(printable => $p->{printable});
    my $rt = CATS::RankTable->new($p);
    $rt->parse_params($p);
    $rt->rank_table;
    $contest->{title} = $rt->{title};
    return if $p->{json};
    my $s = $t->output;

    init_template($p, $template_name);
    $t->param(rank_table_content => $s, printable => $p->{printable});
}

sub _rank_table_icpc_export {
    my ($p) = @_;
    $p->{do_export} or return;
    $p->{icpc_teams} or return 'No teams';
    my $csv = Text::CSV->new({ binary => 1 });
    open my $fh, '<', \$p->{icpc_teams};
    $csv->parse(scalar <$fh>) or return $csv->error_diag;
    2 == grep /^(?:id|name)$/, $csv->fields
        or return 'Must have "id" and "name" columns: ' . join('|', $csv->fields);
    $csv->column_names($csv->fields);
    my $teams = $csv->getline_hr_all($fh) or return $csv->error_diag;
    close $fh;
    @$teams or return 'No teams';
    my $rt = CATS::RankTable->new($p);
    $rt->parse_params($p);
    $rt->rank_table;
    my %team_idx;
    $team_idx{$_->{team_name}} = $_ for @{$rt->{rank}};
    my @unknown;
    my $rank_export = [ map {
        my $r = $team_idx{$_->{name}} or push @unknown, $_->{name};
        $r //= {};
        my ($inst) = $_->{name} =~ /^(.+)(?:\:.+|\s+\d+)$/;
        [
            $_->{id}, $r->{place}, # $_->{name}, $inst,
            join(' ', map $_->{name}, @{$r->{awards}}),
            $r->{total_solved}, $r->{total_time}, '', '', '',
        ];
    } @$teams ];
    return 'Unknown teams: ' . join ' | ', @unknown if @unknown;
    $p->{csv} = [ qw(
        teamId rank
        medalCitation
        problemsSolved totalTime lastProblemTime siteCitation citation) ];
    init_template($p, 'rank_table_icpc_export');
    $t->param(
        icpc_teams => $p->{icpc_teams},
        lv_array_name => 'rank_export',
        rank_export => $rank_export,
    );
    undef;
}

sub rank_table_icpc_export_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'rank_table_icpc_export');
    my $err = _rank_table_icpc_export($p);
    msg(1230, $err) if $err;
}

sub _set_selected {
    my ($data, $selected_list) = @_;
    my %selected;
    @selected{@$selected_list} = undef;
    $_->{selected} = exists $selected{$_->{id}} for @$data;
}

sub rank_table_frame {
    my ($p) = @_;

    #rank_table($p, 'rank_table.htm');
    #init_template($p, 'rank_table_content.htm');
    init_template($p, 'rank_table');

    my $rt = CATS::RankTable->new($p);
    $rt->get_contests_info($uid);
    $contest->{title} = $rt->{title};

    my $sites = @{$p->{sites}} ? $dbh->selectall_arrayref(_u $sql->select(
        'sites', 'id, name', { id => $p->{sites} }, 'name')) : [];
    my $groups = @{$p->{groups}} ? $dbh->selectall_arrayref(_u $sql->select(
        'acc_groups', 'id, name', { id => $p->{groups} }, 'name')) : [];
    $t->param(problem_title => join '; ', (map $_->{name}, @$sites), (map $_->{name}, @$groups));

    my $url = sub {
        url_f(shift, CATS::RouteParser::reconstruct($p, clist => $rt->{contest_list}, @_));
    };
    $t->param(
        href_rank_table_content => $url->('rank_table_content'),
        href_problem_submit => url_f('problems',
            source_text => 1, de_code => $CATS::Globals::de_code_answer_text),
    );
    my $submenu =
        [ { href => $url->('rank_table_content', printable => 1), item => res_str(538) } ];
    if ($is_jury) {
        push @$submenu,
            { href => $url->('rank_table', cache => ($p->{cache} ? 0 : 1)), item => res_str(553) },
            { href => $url->('rank_table', points => ($p->{points} ? 0 : 1)), item => res_str(554) };
    }
    if ($is_root) {
        push @$submenu,
            { href => $url->('rank_table_icpc_export', csv_sep => ','), item => 'ICPC Export' },
    }
    if ($is_jury) {
        my $groups = $dbh->selectall_arrayref(qq~
            SELECT DISTINCT AG.id, AG.name FROM acc_groups AG
            INNER JOIN acc_group_contests AGC ON AGC.acc_group_id = AG.id
            WHERE AGC.contest_id IN ($rt->{contest_list}) ORDER BY AG.name~, { Slice => {} });
        _set_selected($groups, $p->{groups});

        my $sites = $dbh->selectall_arrayref(qq~
            SELECT DISTINCT S.id, S.name FROM sites S
            INNER JOIN contest_sites CS ON CS.site_id = S.id
            WHERE CS.contest_id IN ($rt->{contest_list}) ORDER BY S.name~, { Slice => {} });
        _set_selected($sites, $p->{sites});

        my @ui_fields = qw(
            filter sort show_flags show_logins show_regions points_min points_max
            hide_ooc hide_virtual notime nostats);
        my %route = CATS::RouteParser::reconstruct($p);
        delete @route{qw(groups sites), @ui_fields};
        $t->param(
            route => { %route, cid => $cid, sid => $sid, clist => $rt->{contest_list} },
            groups => $groups,
            sites => $sites,
            map { $_ => $p->{$_} } @ui_fields,
        );
    }
    $t->param(submenu => $submenu, title_suffix => res_str(529));
}

sub rank_table_content_frame {
    my ($p) = @_;
    rank_table($p, 'rank_table_iframe');
}

sub rank_problem_details {
    my ($p) = @_;
    init_template($p, 'rank_problem_details');
    $is_jury or return;

    $p->{pid} or return;

    my $runs = $dbh->selectall_arrayref(q~
        SELECT
            R.id, R.state, R.account_id, R.points
        FROM reqs R WHERE R.contest_id = ? AND R.problem_id = ?
        ORDER BY R.id~, { Slice => {} },
        $cid, $p->{pid});

    for (@$runs) {
        1;
    }
}

1;
