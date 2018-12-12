package CATS::QueryBuilder;

use strict;
use warnings;

use Carp qw(croak);

use CATS::DB;
use CATS::Messages qw(msg);

sub new {
    my ($class, %p) = @_;
    my $self = {
        search => [],
        search_subqueries => [],
        db_searches => {},
        subqueries => {},
        enums => {},
    };
    bless $self, $class;
}

sub parse_search {
    my ($self, $search) = @_;
    my $ident = '[a-zA-Z][a-zA-Z0-9_]*';
    $self->{search} = [];
    $self->{search_subqueries} = [];
    for (split /,\s*/, $search) {
        /^($ident)([!~^=><]?=|>|<|\?|!~)(.*)$/ ? push @{$self->{search}}, [ $1, $3, $2 ] :
        /^($ident)\((\d+|[a-zA-Z][a-zA-Z0-9_.]*)\)$/ ? push @{$self->{search_subqueries}}, [ $1, $2 ] :
        push @{$self->{search}}, [ '', $_, '' ];
    }
    $self;
}

sub regex_op {
    my ($op, $v) = @_;
    $op eq '=' || $op eq '==' ? "^\Q$v\E\$" :
    $op eq '!=' ? "^(?!\Q$v\E)\$" :
    $op eq '^=' ? "^\Q$v\E" :
    $op eq '~=' || $op eq '' ? "\Q$v\E" :
    $op eq '!~' ? "^(?!.*\Q$v\E)" :
    $op eq '?' ? "." :
    die "Unknown search op '$op'";
}

sub sql_op {
    my ($op, $v) = @_;
    $op eq '=' || $op eq '==' ? { '=', $v } :
    $op eq '!=' ? { '!=', $v } :
    $op eq '^=' ? { 'STARTS WITH', $v } :
    $op eq '~=' ? { 'LIKE', '%' . "$v%" } :
    $op eq '!~' ? { 'NOT LIKE', '%' . "$v%" } :
    $op eq '?' ? { '!=', undef, '!=', \q~''~ } :
    $op =~ /^>|>=|<|<=$/ ? { $op, $v } : # SQL-only for now.
    die "Unknown search op '$op'";
}

# <search> ::= <condition> { ',' <condition> }
# <condition> ::= <value> | <field name> { '=' | '==' | '!=' | '^=' | '~=' | '!~' } <value> | <func>(<integer>)
# Spaces are significant around values, but not around keys.
# Values without field name are searched in all fields.
# Different fields are AND'ed, multiple values of the same field are OR'ed.
sub get_mask {
    my ($self) = @_;
    my %mask;
    for my $q (@{$self->{search}}) {
        my ($k, $v, $op) = @$q;
        $self->{db_searches}->{$k} or push @{$mask{$k} ||= []}, regex_op($op, $v);
    }
    for (values %mask) {
        my $s = join '|', @$_;
        $_ = qr/$s/i;
    }
    \%mask;
}

sub make_where {
    my ($self) = @_;
    my %result;
    for my $q (@{$self->{search}}) {
        my ($k, $v, $op) = @$q;
        my $f = $self->{db_searches}->{$k} or next;
        $v = $self->{enums}->{$k}->{$v} // $v;
        push @{$result{$f} //= []}, sql_op($op, $v);
    }
    my (@sq_list, @sq_unknown);
    for my $d (@{$self->{search_subqueries}}) {
        my ($name, $value) = @$d;
        my $sq = $self->{subqueries}->{$name}
            or push @sq_unknown, $name and next;
        $value = $self->{enums}->{$name}->{$value} // $value;
        if ($sq->{m}) {
            my @msg_args = $sq->{t} ? $dbh->selectrow_array($sq->{t}, undef, $value) : ();
            msg($sq->{m}, @msg_args);
        }
        # SQL::Abstract uses double reference to designate subquery.
        push @sq_list, \[ $sq->{sq} => $value ];
    }
    msg(1143, join ',', @sq_unknown) if @sq_unknown;
    @sq_list ? { -and => [ (%result ? \%result : ()), @sq_list ] } : \%result;
}

sub add_db_search {
    my ($self, $k, $v) = @_;
    $self->{db_searches}->{$k} and croak "Duplicate search: $k";
    $self->{db_searches}->{$k} = $v;
}

sub define_db_searches {
    my ($self, $db_searches) = @_;
    if (ref $db_searches eq 'ARRAY') {
        for (@$db_searches) {
            $self->add_db_search((m/\.(.+)$/ ? $1 : $_), $_);
        }
    }
    elsif (ref $db_searches eq 'HASH') {
        for (keys %$db_searches) {
            $self->add_db_search($_, $db_searches->{$_});
        }
    }
    else {
        die;
    }
}

# sql OR { sq => sql, m => msg id, t => msg arguments sql }

sub define_subqueries {
    my ($self, $subqueries) = @_;
    for my $k (keys %$subqueries) {
        $self->{subqueries}->{$k} and croak "Duplicate subquery: $k";
        $self->{subqueries}->{$k} =
            ref $subqueries->{$k} ? $subqueries->{$k} : { sq => $subqueries->{$k} };
    }
}

sub define_enums {
    my ($self, $enums) = @_;
    for my $k (keys %$enums) {
        croak "Duplicate enum: $k" if $self->{enums}->{$k};
        $self->{enums}->{$k} = $enums->{$k};
    }
}

sub extract_search_values {
    my ($self, $name) = @_;
    my @result = map {
        my ($k, $v) = @$_;
        $self->{enums}->{$k}->{$v} // $v;
    } grep $_->[0] eq $name, @{$self->{search}};
    $self->{search} = [ grep $_->[0] ne $name, @{$self->{search}} ];
    \@result;
}

sub search_subquery_value {
    my ($self, $name) = @_;
    $_->[0] eq $name and return $_->[1] for @{$self->{search_subqueries}};
    undef;
}

sub searches_subset_of {
    my ($self, $set) = @_;
    for (@{$self->{search}}, @{$self->{search_subqueries}}) {
        $set->{$_->[0]} or return 0;
    }
    1;
}

1;
