package CATS::UI::Sites;

use strict;
use warnings;

use Encode;

use CATS::DB;
use CATS::Form qw(validate_string_length);
use CATS::Globals qw($cid $contest $t $is_jury $is_root $user);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;
use CATS::Time;

my $str1_200 = CATS::Field::str_length(1, 200);
my $str0_200 = CATS::Field::str_length(0, 200);

my $person_phone_sql = qq~
    COALESCE((SELECT LIST(' ' || C.handle) FROM contacts C
        WHERE C.account_id = A.id AND C.contact_type_id = $CATS::Globals::contact_phone AND C.is_actual = 1), '')~;

our $form = CATS::Form1->new(
    table => 'sites',
    fields => [
        [ name => 'name', validators => [ $str1_200 ], caption => 601, ],
        [ name => 'region', validators => [ $str0_200 ], caption => 654 ],
        [ name => 'city', validators => [ $str0_200 ], caption => 655, ],
        [ name => 'org_name', validators => [ $str1_200 ], caption => 656, editor => { size => 100 }, ],
        [ name => 'address', validators => [ $str0_200 ], caption => 657, editor => { size => 100 }, ],
    ],
    href_action => 'sites_edit',
    descr_field => 'name',
    template_var => 'site',
    msg_deleted => 1066,
    msg_saved => 1067,
    before_display => sub {
        my ($fd, $p) = @_;
        $fd->{contests} = $is_root && $fd->{id} ? $dbh->selectall_arrayref(qq~
            SELECT C.title, C.start_date,
                (SELECT LIST(A.team_name || $person_phone_sql, ', ') FROM contest_accounts CA
                INNER JOIN accounts A ON A.id = CA.account_id
                WHERE CA.contest_id = C.id AND CA.site_id = CS.site_id AND CA.is_site_org = 1) AS orgs
            FROM contests C
            INNER JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = ?
            ORDER BY C.start_date DESC ROWS 50~, { Slice => {} },
            $fd->{id}) : [];
        warn @{$fd->{contests}};
    },
);

sub sites_edit_frame {
    my ($p) = @_;
    init_template($p, 'sites_edit.html.tt');
    $user->privs->{edit_sites} or return;
    $form->edit_frame($p, redirect => [ 'sites' ]);
}

sub common_searches {
    my ($lv) = @_;
    $lv->define_db_searches($form->{sql_fields});
    my $name_sql = q~
        SELECT A.team_name FROM accounts A WHERE A.id = ?~;
    $lv->define_subqueries({
        has_contest => { sq => q~EXISTS (
            SELECT 1 FROM contest_sites CS WHERE CS.contest_id = ? AND CS.site_id = S.id)~,
            m => 1047, t => q~
            SELECT C.title FROM contests C WHERE C.id = ?~
        },
        has_user => { sq => qq~EXISTS (
            SELECT 1 FROM contest_accounts CA
            WHERE CA.site_id = S.id AND CA.account_id = ?)~,
            m => 1032, t => $name_sql
        },
        has_org => { sq => qq~EXISTS (
            SELECT 1 FROM contest_accounts CA
            WHERE CA.site_id = S.id AND CA.account_id = ? AND CA.is_site_org = 1)~,
            m => 1034, t => $name_sql
        },
    });
}

sub sites_frame {
    my ($p) = @_;
    $user->privs->{edit_sites} or return;

    init_template($p, 'sites.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'sites');

    $form->delete_or_saved($p);

    $lv->define_columns(url_f('sites'), 0, 0, [
        { caption => res_str(601), order_by => 'name',     width => '20%' },
        { caption => res_str(654), order_by => 'region',   width => '15%', col => 'Rg' },
        { caption => res_str(655), order_by => 'city',     width => '15%', col => 'Ct' },
        { caption => res_str(656), order_by => 'org_name', width => '20%', col => 'On' },
        { caption => res_str(657), order_by => 'address',  width => '20%', col => 'Ad' },
        { caption => res_str(645), order_by => 'contests', width => '10%', col => 'Cc' },
    ]);
    common_searches($lv);

    my $count_fld = !$lv->visible_cols->{Cc} ? 'NULL' : q~
        (SELECT COUNT(*) FROM contest_sites CS WHERE CS.site_id = S.id)~;

    my ($q, @bind) = $sql->select('sites S',
        [ 'id', @{$form->{sql_fields}}, "$count_fld AS contests" ], $lv->where);
    my $c = $dbh->prepare("$q " . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit => url_f('sites_edit', id => $row->{id}),
            href_delete => url_f('sites', 'delete' => $row->{id}),
            href_contests => url_f('contests', search => "has_site($row->{id})", filter => 'all'),
        );
    };
    $lv->attach(url_f('sites'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('sites') ], editable => $is_root)
        if $is_jury;
}

sub contest_sites_edit_save {
    my ($p, $s) = @_;
    $p->{save} or return;
    CATS::Time::set_diff_time($s, $p, 'diff') or return;
    CATS::Time::set_diff_time($s, $p, 'ext') or return;

    $dbh->do(_u $sql->update('contest_sites',
        { diff_time => $s->{diff_time}, ext_time => $s->{ext_time} },
        { site_id => $p->{site_id}, contest_id => $cid }
    ));
    ($s->{contest_start_offset}, $s->{contest_finish_offset}) = $dbh->selectrow_array(q~
        SELECT C.start_date + CS.diff_time, C.start_date + CS.diff_time  + CS.ext_time
        FROM contest_sites CS
        INNER JOIN contests C ON C.id = CS.contest_id
        WHERE CS.site_id = ? AND CS.contest_id = ?~, undef,
        $s->{id}, $cid) or return;
    $dbh->commit;
    msg($s->{diff_time} ? 1160 : 1161, $s->{site_name});
    msg($s->{ext_time} ? 1164 : 1165, $s->{site_name});
}

sub contest_sites_edit_frame {
    my ($p) = @_;
    $is_jury or return;
    my $site_id = $p->{site_id} or return;

    init_template($p, 'contest_sites_edit.html.tt');

    my $s = $dbh->selectrow_hashref(qq~
        SELECT
            S.id, S.name AS site_name, CS.diff_time, CS.ext_time, CS.contest_id,
            C.title AS contest_name,
            C.start_date AS contest_start,
            C.start_date + COALESCE(CS.diff_time, 0) AS contest_start_offset,
            C.finish_date AS contest_finish,
            $CATS::Time::contest_site_finish_sql AS contest_finish_offset,
            (SELECT COUNT(*) FROM contest_accounts CA
                WHERE CA.site_id = S.id AND CA.contest_id = C.id) AS users_count
        FROM sites S
        INNER JOIN contest_sites CS ON CS.site_id = S.id
        INNER JOIN contests C ON C.id = CS.contest_id
        WHERE CS.site_id = ? AND CS.contest_id = ?~, { Slice => {} },
        $site_id, $cid) or return;
    contest_sites_edit_save($p, $s);

    $t->param(
        href_contest => url_f('contest_params', id => $s->{contest_id}),
        href_users => url_f('users', search => "site_id=$s->{id}"),
        ($user->privs->{edit_sites} ? (href_site => url_f('sites_edit', id => $s->{id})) : ()),
        s => $s,
        formatted_diff_time => CATS::Time::format_diff($s->{diff_time}, display_plus => 1),
        formatted_ext_time => CATS::Time::format_diff($s->{ext_time}, display_plus => 1),
        title_suffix => $s->{name},
    );
}

sub contest_sites_add {
    my ($p) = @_;
    my @checked = grep $_ && $_ > 0, @{$p->{check}} or return;
    my $sth_add= $dbh->prepare(q~
        INSERT INTO contest_sites (contest_id, site_id) VALUES (?, ?)~);
    my $count = 0;
    for (@checked) {
        next if $dbh->selectrow_array(q~
            SELECT 1 FROM contest_sites WHERE contest_id = ? AND site_id = ?~, undef,
            $cid, $_);
        $count += $sth_add->execute($cid, $_);
    }
    $dbh->commit;
    msg(1068, $count);
}

sub contest_sites_delete {
    my ($p) = @_;
    my $site_id = $p->{delete} or return;
    my ($name) = $dbh->selectrow_array(q~
        SELECT name FROM sites WHERE id = ?~, undef,
        $site_id) or return;

    $dbh->selectrow_array(q~
        SELECT 1 FROM contest_accounts CA WHERE CA.contest_id = ? AND CA.site_id = ? ROWS 1~, undef,
        $cid, $site_id) and return msg(1025);
    $dbh->do(q~
        DELETE FROM contest_sites WHERE contest_id = ? AND site_id = ?~, undef,
        $cid, $site_id);
    $dbh->commit;
    msg(1066, $name);
}

sub contest_sites_frame {
    my ($p) = @_;

    init_template($p, 'contest_sites.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'contest_sites');
    $is_jury || $user->{is_site_org} || $contest->{show_sites} or return;

    $lv->define_columns(url_f('contest_sites'), 0, 0, [
        { caption => res_str(601), order_by => 'name'       , width => '15%' },
        { caption => res_str(654), order_by => 'region'     , width => '15%', col => 'Rg' },
        { caption => res_str(655), order_by => 'city'       , width => '15%', col => 'Ci' },
        { caption => res_str(656), order_by => 'org_name'   , width => '15%', col => 'Oc' },
        ($is_jury || $user->{is_site_org} ? (
        { caption => res_str(659), order_by => 'org_person' , width => '15%', col => 'Op' },
        { caption => res_str(632), order_by => 'diff_time'  , width => '15%', col => 'Dt' },
        ): ()),
        { caption => res_str(658), order_by => 'users_count', width => '15%', col => 'Pt' },
    ]);
    common_searches($lv);

    if ($is_jury) {
        contest_sites_delete($p);
        contest_sites_add($p) if $p->{add};
    }

    my $org_person_phone = $user->privs->{is_root} ? qq~ || $person_phone_sql~ : '';
    my $org_person_sql = $lv->visible_cols->{Op} ? qq~
        SELECT LIST(A.team_name$org_person_phone, ', ') FROM contest_accounts CA
        INNER JOIN accounts A ON A.id = CA.account_id
        WHERE CA.contest_id = CS.contest_id AND CA.site_id = S.id AND CA.is_site_org = 1
        ORDER BY 1~ : 'NULL';

    my $users_count_sql = $lv->visible_cols->{Pt} ? q~
        SELECT COUNT(*) FROM contest_accounts CA
        WHERE CA.contest_id = CS.contest_id AND CA.site_id = S.id AND CA.is_hidden = 0~ : 'NULL';
    my $users_count_ooc_sql = $lv->visible_cols->{Pt} ? q~
        SELECT COUNT(*) FROM contest_accounts CA
        WHERE CA.contest_id = CS.contest_id AND CA.site_id = S.id AND CA.is_hidden = 0 AND is_ooc = 1~ : 'NULL';
    my $is_used_cond = $is_jury ? '1 = 1' : 'CS.site_id IS NOT NULL';
    my $sth = $dbh->prepare(qq~
        SELECT
            S.id, (CASE WHEN CS.site_id IS NULL THEN 0 ELSE 1 END) AS is_used,
            S.name, S.region, S.city, S.org_name, CS.diff_time, CS.ext_time,
            ($org_person_sql) AS org_person,
            ($users_count_sql) AS users_count,
            ($users_count_ooc_sql) AS users_count_ooc
        FROM sites S
        LEFT JOIN contest_sites CS ON CS.site_id = S.id AND CS.contest_id = ?
        WHERE $is_used_cond ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            formatted_time => CATS::Time::format_diff_ext($row->{diff_time}, $row->{ext_time}, display_plus => 1),
            ($user->privs->{edit_sites} ? (href_site => url_f('sites_edit', id => $row->{id})) : ()),
            ($is_jury ? (href_delete => url_f('contest_sites', 'delete' => $row->{id})) : ()),
            href_edit => url_f('contest_sites_edit', site_id => $row->{id}),
            href_users => url_f('users', search => "site_id=$row->{id}"),
            href_console => url_f('console',
                i_value => -1, se => 'sites', show_results => 1,
                search => "site_id=$row->{id}" . ($is_root ? ',contest_id=this' : '')),
            href_rank_table => url_f('rank_table', sites => $row->{id}),
        );
    };
    $lv->attach(url_f('contest_sites'), $fetch_record, $sth);
    $t->param(submenu => [
        ($is_jury ? { item => res_str(588), href => url_f('contest_sites', search => 'is_used=1') } : ()),
    ]);
}

1;
