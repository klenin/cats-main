package CATS::Contest;

use strict;
use warnings;

sub database_fields {qw(
    id title short_descr
    start_date finish_date freeze_date defreeze_date
    closed penalty ctype rules max_reqs
    is_official run_all_tests
    show_all_tests show_test_resources show_checker_comment show_packages show_test_data show_flags show_sites
    local_only is_hidden max_reqs_except
)}

use fields (database_fields(), qw(server_time time_since_start time_since_finish time_since_defreeze tags));

use CATS::Config qw(cats_dir);
use CATS::Contest::Utils;
use CATS::DB;
use CATS::Messages qw(msg);

sub new {
    my ($self, $init) = @_;
    $self = fields::new($self) unless ref $self;
    if ($init) {
        $self->{$_} = $init->{$_} for keys %$init;
    }
    $self;
}

sub time_since_sql { "CAST(CURRENT_TIMESTAMP - $_[0]_date AS DOUBLE PRECISION) AS time_since_$_[0]" }

sub load {
    my ($self, $contest_id, $fields) = @_;
    $fields //= [
        database_fields(),
        'CURRENT_TIMESTAMP AS server_time',
        map time_since_sql($_), qw(start finish defreeze)
    ];
    my $r = $contest_id ? CATS::DB::select_row('contests', $fields, { id => $contest_id }) : undef;
    # Choose training contest by default.
    $r or $r = CATS::DB::select_row('contests', $fields, { ctype => 1 }) or die 'No contest';
    @$self{keys %$r} = values %$r;
    $self;
}

sub is_practice {
    my ($self) = @_;
    defined $self->{ctype} && $self->{ctype} == 1;
}

sub has_started {
    my ($self, $offset) = @_;
    $self->{time_since_start} >= ($offset || 0);
}

sub has_finished {
    my ($self, $offset) = @_;
    $self->{time_since_finish} >= ($offset || 0);
}

sub has_finished_for {
    my ($self, $u) = @_;
    $self->has_finished($u->{diff_time} + $u->{ext_time});
}

sub current_official {
    $dbh->selectrow_hashref(q~
        SELECT id, title FROM contests
            WHERE CURRENT_TIMESTAMP BETWEEN start_date AND finish_date AND is_official = 1~);
}

sub used_problem_codes {
    my ($self) = @_;
    $dbh->selectcol_arrayref(q~
        SELECT code FROM contest_problems WHERE contest_id = ? ORDER BY 1~, undef,
        $self->{id}
    );
}

sub register_account {
    my ($self, %p) = @_;
    $p{account_id} or die;
    $p{contest_id} ||= $self->{id};
    $p{$_} ||= 0 for (qw(is_jury is_pop is_hidden is_virtual is_site_org diff_time));
    $p{$_} ||= 1 for (qw(is_ooc is_remote));
    $p{id} = new_id;
    $dbh->do(_u $sql->insert('contest_accounts', \%p));
    return if $p{is_hidden};
    my $p = cats_dir() . "./rank_cache/$p{contest_id}#";
    unlink <$p*>;
}

sub contest_group_auto_new {
    my ($clist) = @_;
    my @clist = sort { $a <=> $b } @$clist;
    @clist && @clist < 100 or return;
    $clist = join ',', @clist;
    return msg(1090) if CATS::Contest::Utils::contest_group_by_clist($clist);
    my $names = $dbh->selectcol_arrayref(_u
        $sql->select('contests', 'title', { id => \@clist })) or return;
    my $id = new_id;
    my $name = CATS::Contest::Utils::common_prefix(@$names) || "Group $id";
    $dbh->do(q~
        INSERT INTO contest_groups (id, name, clist)
        VALUES (?, ?, ?)~, undef,
        $id, $name, $clist);
    $dbh->commit;
    msg(1089, $name);
}

1;
