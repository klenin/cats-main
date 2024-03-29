package CATS::Report;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::Utils qw(group_digits);

use CATS::Judge;

sub new {
    bless {
        short => {},
        long => {},
    }, shift;
}

sub construct_short {
    my ($self) = @_;
    my $s = $self->{short};
    %$s ? join ' ', map "$_=$s->{$_}", sort keys %$s : 'ok';
}

sub construct_long {
    my ($self) = @_;
    join "\n", map "$_: $self->{long}->{$_}", sort keys %{$self->{long}};
}

sub log_url {
    CATS::Utils::absolute_url_function(
        'run_log', rid => $_[0]->{id}, cid => $_[0]->{contest_id}, sid => 'z')
}

our $items = [
    {
        name => 'ReqQ', long => 'Queue length', short => 'Q',
        get => sub {
            my $ql = $dbh->selectrow_array(qq~
                SELECT COUNT(*) FROM reqs R
                WHERE R.state = ? AND R.submit_time > CURRENT_TIMESTAMP - 30~, undef,
                $cats::st_not_processed);
            ($ql, ($ql > 1 ? $ql : undef));
        },
    },
    {
        name => 'JobQ', long => 'Job queue', short => 'JQ',
        get => sub {
            my $jql = $dbh->selectrow_array(q~
                SELECT COUNT(*) FROM jobs_queue~);
            ($jql, ($jql > 1 ? $jql : undef));
        },
    },
    {
        name => 'ReqT', long => 'Requests today', short => '',
        get => sub {
            scalar $dbh->selectrow_array(q~
                SELECT COUNT(*) FROM reqs R
                WHERE R.submit_time > CURRENT_TIMESTAMP - 1~);
        },
    },
    {
        name => 'JobT', long => 'Jobs today', short => '',
        get => sub {
            scalar $dbh->selectrow_array(q~
                SELECT COUNT(*) FROM jobs J
                WHERE J.create_time > CURRENT_TIMESTAMP - 1~);
        },
    },
    {
        name => 'UH', long => 'Unhandled errors', short => 'UH',
        get => sub {
            my $u = $dbh->selectall_arrayref(qq~
                SELECT R.id, R.contest_id FROM reqs R
                WHERE R.state = $cats::st_unhandled_error AND R.submit_time > CURRENT_TIMESTAMP - 30
                ORDER BY R.submit_time DESC~, { Slice => {} });
            ((join "\n", scalar(@$u), map '    ' . log_url($_), @$u), (@$u ? scalar @$u : undef));
        },
    },
    {
        name => 'Judge', long => 'Judges alive / total', short => 'J',
        get => sub {
            my ($jalive, $jtotal) = CATS::Judge::get_active_count;
            my $j = "$jalive/$jtotal";
            ($j, ($jalive < $jtotal || !$jtotal ? $j : undef));
        },
    },
    {
        name => 'Quest', long => 'Questions unanswered', short => '?',
        get => sub {
            my $q = $dbh->selectrow_array(q~
                SELECT COUNT(*) FROM questions Q
                WHERE Q.clarified = 0 AND Q.submit_time > CURRENT_TIMESTAMP - 30~);
            ($q, $q || undef);
        },
    },
    {
        name => 'Prob', long => 'Problems changed', short => '',
        get => sub {
            my ($p) = $dbh->selectall_arrayref(q~
                SELECT id, title
                FROM problems P WHERE CURRENT_TIMESTAMP - P.upload_date <= 1~, { Slice => {} });
            (@$p ? join ', ', map qq~"$_->{title}"~, @$p : undef);
        },
    },
    {
        name => 'Log', long => 'Log dump size', short => '',
        get => sub {
            my ($length) = $dbh->selectrow_array(q~
                SELECT SUM(OCTET_LENGTH(L.dump))
                FROM logs L INNER JOIN jobs J ON J.id = L.job_id
                WHERE J.create_time > CURRENT_TIMESTAMP - 1~);
            ($length ? group_digits($length, '_') : undef);
        },
    },
];

1;
