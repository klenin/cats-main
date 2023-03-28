package CATS::UI::Topics;

use strict;
use warnings;

use CATS::Contest::Utils;
use CATS::DB;
use CATS::Form;
use CATS::Globals qw($cid $is_jury $t $user);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);

my $ordering = CATS::Field::int_range(min => 0, max => 100000);

sub _rename_problems {
    my ($old_prefix, $new_prefix) = @_;
    my $problems = $dbh->selectall_arrayref(q~
        SELECT id, code FROM contest_problems
        WHERE contest_id = ? AND code STARTS WITH ?~, { Slice => {} },
        $cid, $old_prefix);
    @$problems or return;
    my $sth = $dbh->prepare(q~
        UPDATE contest_problems SET code = ? WHERE id = ?~);
    my $count = 0;
    for (@$problems) {
        $_->{code} =~ s/^\Q$old_prefix\E/$new_prefix/;
        $count += $sth->execute($_->{code}, $_->{id});
    }
    $dbh->commit if $count;
    $count;
}

our $form = CATS::Form->new(
    table => 'topics',
    fields => [
        [ name => 'contest_id', caption => 603, before_save => sub { $cid } ],
        [ name => 'name', validators => [ CATS::Field::str_length(1, 200) ], caption => 601, ],
        [ name => 'description', caption => 620, editor => { size => 80 } ],
        [ name => 'code_prefix', validators => [ CATS::Field::str_length(0, 100) ], caption => 818, ],
        [ name => 'is_hidden', validators => [ $CATS::Field::bool ], %CATS::Field::default_zero,
            caption => 614, ],
    ],
    href_action => 'topics_edit',
    descr_field => 'name',
    template_var => 'tp',
    msg_deleted => 1242,
    msg_saved => 1243,
    before_display => sub {
        my ($fd, $p) = @_;
        my $prefix = $fd->{indexed}->{code_prefix}->{value} // '';
        my $name = $fd->{indexed}->{name}->{value} // '';
        $fd->{data}->{problems} = $prefix ne '' && $dbh->selectall_arrayref(q~
            SELECT P.id, CP.code, P.title
            FROM problems P INNER JOIN contest_problems CP ON CP.problem_id = P.id
            WHERE CP.contest_id = ? AND CP.code STARTS WITH ?
            ORDER BY CP.code~, { Slice => {} },
            $cid, $prefix);
        $fd->{data}->{href_problems} = $prefix ne '' && url_f('problems', search => 'code^=' . $prefix);
        $name =~ s/\s/_/g;
        $fd->{data}->{href_contests} =
            $name ne '' && url_f('contests', search => "has_topic_like($name)");
    },
    validators => [ sub {
        my ($fd, $p) = @_;
        1;
    }, ],
    before_save => sub {
        my ($fd, $p) = @_;
        $fd->{data}->{old_code_prefix} = $fd->{id} && $dbh->selectrow_array(q~
            SELECT code_prefix FROM topics WHERE id = ?~, undef,
            $fd->{id});
    },
    after_save => sub {
        my ($fd, $p) = @_;
        if ($p->{rename} && defined(my $old = $fd->{data}->{old_code_prefix})) {
            my $new = $fd->{indexed}->{code_prefix}->{value} // '';
            $fd->{data}->{renamed_count} = _rename_problems($old, $new) if $old ne $new;
        }
    },
    redirect_cancel => [ 'topics' ],
    redirect_save => sub {
        my ($fd, $p) = @_;
        [ 'topics', renamed => $fd->{data}->{renamed_count} ];
    },
);

sub topics_edit_frame {
    my ($p) = @_;
    init_template($p, 'topics_edit.html.tt');
    $is_jury or return;
    CATS::Contest::Utils::contest_submenu('topics');
    $form->edit_frame($p);
}

sub _import_from_contest {
    my ($source_cid, $include_hidden) = @_;

    my ($source_cid_found, $source_is_jury) = $dbh->selectrow_array(q~
        SELECT C.id, CA.is_jury
        FROM contests C
        LEFT JOIN contest_accounts CA ON CA.contest_id = C.id and CA.account_id = ?
        WHERE C.id = ? AND (C.is_hidden = 0 OR CA.is_jury = 1)~, undef,
        $user->{id}, $source_cid);

    $source_cid_found or return;

    my $hidden_cond = $source_is_jury && $include_hidden ? '' : ' AND is_hidden = 0';
    my $topics = $dbh->selectall_arrayref(qq~
        SELECT id, code_prefix, name, description, is_hidden
        FROM topics
        WHERE contest_id = ?$hidden_cond~, { Slice => {} },
        $source_cid);
    @$topics or return;
    my $insert_sth = $dbh->prepare(q~
        INSERT INTO topics (id, contest_id, code_prefix, name, description, is_hidden)
        VALUES (?, ?, ?, ?, ?, ?)~);
    my $cnt = 0;
    for (@$topics) {
        $cnt += $insert_sth->execute(new_id, $cid, @$_{qw(code_prefix name description is_hidden)});
    }
    $dbh->commit if $cnt;
    msg(1251, $cnt);
}

sub topics_frame {
    my ($p) = @_;

    init_template($p, 'topics');
    $is_jury or return;

    $form->delete_or_saved($p);
    msg(1245, $p->{renamed}) if defined $p->{renamed};

    _import_from_contest($p->{source_cid}, $p->{include_hidden}) if $p->{from_contest};

    my $lv = CATS::ListView->new(web => $p, name => 'topics', url => url_f('topics'));

    $lv->default_sort(0)->define_columns([
        { caption => res_str(818), order_by => 'code_prefix', width => '20%' },
        { caption => res_str(601), order_by => 'name', width => '50%' },
        { caption => res_str(620), order_by => 'description', width => '50%', col => 'De' },
        { caption => res_str(614), order_by => 'is_hidden', width => '10%', col => 'Hd' },
    ]);
    $lv->define_db_searches([ qw (id code_prefix name descrition is_hidden) ]);
    $lv->default_searches([ qw(code_prefix name) ]);
    my $sth = $dbh->prepare(q~
        SELECT T.id, T.code_prefix, T.name, T.description, T.is_hidden
        FROM topics T
        WHERE T.contest_id = ?~ . $lv->maybe_where_cond . $lv->order_by);
    $sth->execute($cid, $lv->where_params);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        (
            %$row,
            href_problems => url_f('problems', search => 'code^=' . ($row->{code_prefix} // '')),
            href_edit => url_f('topics_edit', id => $row->{id}),
            href_delete => url_f('topics', 'delete' => $row->{id}),
        );
    };
    $lv->attach($fetch_record, $sth);
    CATS::Contest::Utils::contest_submenu('topics');
    $t->param(
        href_find_contests => url_f('api_find_contests'),
    );
}

1;
