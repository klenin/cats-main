package CATS::UI::Sites;

use strict;
use warnings;

use Encode;

use CATS::DB;
use CATS::Form qw(validate_string_length);
use CATS::ListView;
use CATS::Misc qw(
    $cid $t $is_jury $is_root $privs
    init_template msg res_str url_f);
use CATS::References;
use CATS::Web qw(param url_param);

sub fields() {qw(name region city org_name address)}

my $form = CATS::Form->new({
    table => 'sites',
    fields => [ map +{ name => $_ }, fields ],
    templates => { edit_frame => 'sites_edit.html.tt' },
    href_action => 'sites',
});

sub edit_frame {
    $form->edit_frame;
}

sub edit_save {
    validate_string_length(param('name'), 601, 1, 100) or return;
    $form->edit_save()
        and msg(1067, Encode::decode_utf8(param('name')));
}

sub sites_frame {
    $privs->{edit_sites} or return;
    defined url_param('new') || defined url_param('edit') and return edit_frame;

    my $lv = CATS::ListView->new(name => 'sites', template => 'sites.html.tt');

    if (my $site_id = url_param('delete')) {
        if (my ($name) = $dbh->selectrow_array(q~
            SELECT name FROM sites WHERE id = ?~, undef,
            $site_id)
        ) {
            $dbh->do(q~
                DELETE FROM sites WHERE id = ?~, undef,
                $site_id);
            $dbh->commit;
            msg(1066, $name);
        }
    }
    defined param('edit_save') and edit_save;

    $lv->define_columns(url_f('sites'), 0, 0, [
        { caption => res_str(601), order_by => '2', width => '20%' },
        { caption => res_str(654), order_by => '3', width => '15%' },
        { caption => res_str(655), order_by => '4', width => '15%' },
        { caption => res_str(656), order_by => '5', width => '20%' },
        { caption => res_str(657), order_by => '6', width => '30%' },
    ]);

    $lv->define_db_searches([ fields ]);

    my ($q, @bind) = $sql->select('sites', [ 'id', fields ], $lv->where);
    my $c = $dbh->prepare("$q " . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            href_edit => url_f('sites', edit => $row->{id}),
            href_delete => url_f('sites', 'delete' => $row->{id})
        );
    };
    $lv->attach(url_f('sites'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('sites') ], editable => $is_root)
        if $is_jury;
}

sub contest_sites_add {
    my @checked = grep $_ && $_ > 0, param('check') or return;
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
    my $site_id = url_param('delete') or return;
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
    $is_jury or return;

    my $lv = CATS::ListView->new(name => 'contest_sites', template => 'contest_sites.html.tt');
    $lv->define_columns(url_f('contest_sites'), 0, 0, [
        { caption => res_str(601), order_by => '3', width => '20%' },
        { caption => res_str(654), order_by => '4', width => '15%' },
        { caption => res_str(655), order_by => '5', width => '15%' },
        { caption => res_str(656), order_by => '6', width => '20%' },
        { caption => res_str(658), order_by => '7', width => '10%' },
    ]);
    $lv->define_db_searches([ fields ]);

    contest_sites_delete;
    contest_sites_add if param('add');

    my $sth = $dbh->prepare(q~
        SELECT
            S.id, (CASE WHEN CS.site_id IS NULL THEN 0 ELSE 1 END) AS is_used,
            S.name, S.region, S.city, S.org_name,
            (SELECT COUNT(*) FROM contest_accounts CA WHERE CA.contest_id = ? AND CA.site_id = S.id) AS users_count
        FROM sites S
        LEFT JOIN contest_sites CS ON CS.site_id = S.id AND CS.contest_id = ?
        WHERE 1 = 1 ~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $cid, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            ($privs->{edit_sites} ? (href_edit => url_f('sites', edit => $row->{id})) : ()),
            href_delete => url_f('contest_sites', 'delete' => $row->{id}),
            href_users => url_f('users', search => "site_id=$row->{id}"),
        );
    };
    $lv->attach(url_f('contest_sites'), $fetch_record, $sth);
    $t->param(is_jury => $is_jury);
}

1;
