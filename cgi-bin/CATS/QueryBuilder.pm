package CATS::QueryBuilder;

use strict;
use warnings;

use Carp qw(croak);

use CATS::DB;
use CATS::Messages qw(msg res_str);

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
        /^($ident)([!~^=><]?=|>|<|\?\??|!~)(.*)$/ ? push @{$self->{search}}, [ $1, $3, $2 ] :
        /^(\!)?($ident)\((\d+|\p{L}(?:\p{L}|\d|[_.])*)\)$/ ?
            push @{$self->{search_subqueries}}, [ $2, $3, $1 ? 1 : 0 ] :
        push @{$self->{search}}, [ '', $_, '' ];
    }
    $self;
}

sub regex_op {
    my ($op, $v) = @_;
    $op eq '=' || $op eq '==' ? "^\Q$v\E\$" :
    $op eq '!=' ? "^(?!\Q$v\E).*\$" :
    $op eq '^=' ? "^\Q$v\E" :
    $op eq '~=' || $op eq '' ? "\Q$v\E" :
    $op eq '!~' ? "^(?!.*\Q$v\E)" :
    $op eq '?' ? '.' :
    $op eq '??' ? '^$' :
    $op =~ /^>|>=|<|<=$/ ? "^(.+)(?(?{\$1$op\Q$v\E})|(*F))\$" :
    die "Unknown search op '$op'";
}

sub sql_op {
    my ($op, $v) = @_;
    $op eq '=' || $op eq '==' ? { '=', $v } :
    $op eq '!=' ? { '!=', $v } :
    $op eq '^=' ? { 'STARTS WITH', $v } :
    $op eq '~=' ? { 'LIKE', '%' . "$v%" } :
    $op eq '!~' ? { 'NOT LIKE', '%' . "$v%" } :
    $op eq '?' ? { '!=', undef } :
    $op eq '??' ? { '=', undef } :
    $op =~ /^>|>=|<|<=$/ ? { $op, $v } :
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
        use re 'eval'; # We use ?{...} for inequality comparisons.
        $_ = qr/$s/i;
    }
    \%mask;
}

sub _where_msg {
    my ($sq, $value, $negate) = @_;
    $sq->{m} or return;
    my @msg_args =
        !exists $sq->{t} ? die :
        !$sq->{t} ? $value :
        $dbh->selectrow_array($sq->{t}, undef, $value)
        or return msg(1222, $value);
    $negate ? msg(1212, res_str($sq->{m}, @msg_args)) : msg($sq->{m}, @msg_args);
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
        my ($name, $value, $negate) = @$d;
        my $sq = $self->{subqueries}->{$name}
            or push @sq_unknown, $name and next;
        $value = $self->{enums}->{$name}->{$value} // $value;
        _where_msg($sq, $value, $negate);
        # SQL::Abstract uses double reference to designate subquery.
        my $sql_sq = \[ $sq->{sq} => $value ];
        push @sq_list, $negate ? { -not_bool => $sql_sq } : $sql_sq;
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
