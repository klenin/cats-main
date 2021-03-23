package CATS::QueryBuilder;

use strict;
use warnings;

use Carp qw(croak);

use CATS::DB;
use CATS::Messages qw(msg res_str);

sub new {
    my ($class, %p) = @_;
    my $self = {
        query => '',
        search => [],
        search_subqueries => [],
        search_defaults => [],
        search_casts => {},
        db_searches => {},
        default_searches => [],
        subqueries => {},
        enums => {},
    };
    bless $self, $class;
}

sub parse_search {
    my ($self, $query) = @_;
    $self->{query} = $query;
    my $ident = '[a-zA-Z][a-zA-Z0-9_]*';
    $self->{search} = [];
    $self->{search_subqueries} = [];
    $self->{search_defaults} = [];
    for (split /,\s*/, $query) {
        /^($ident|\*)([!~^=><]?=|>|<|\?\??|!~|\!\^)(.*)$/ ?
            push @{$self->{search}}, [ $1 eq '*' ? '' : $1, $3, $2 ] :
        /^(\!)?($ident)\(((?:\p{L}|\d|[_.-])+)\)$/ ?
            push @{$self->{search_subqueries}}, [ $2, $3, $1 ? 1 : 0 ] :
            push @{$self->{search_defaults}}, $_;
    }
    $self;
}

sub search { $_[0]->{search} }

sub number_like_filter {
    my ($v) = @_;
    $v =~ tr/0-9.eE+-//cd;
    $v || 0;
}

sub regex_op {
    my ($op, $v) = @_;
    $op eq '=' || $op eq '==' ? "^\Q$v\E\$" :
    $op eq '!=' ? "^(?!\Q$v\E\$).*\$" :
    $op eq '^=' ? "^\Q$v\E" :
    $op eq '!^' ? "^(?!\Q$v\E).*\$" :
    $op eq '~=' ? "\Q$v\E" :
    $op eq '!~' ? "^(?!.*\Q$v\E)" :
    $op eq '?' ? '.' :
    $op eq '??' ? '^$' :
    $op =~ /^>|>=|<|<=$/ ? sprintf('^(.+)(?(?{$1%s%s})|(*F))$', $op, number_like_filter($v)) :
    die "Unknown search op '$op'";
}

sub sql_op {
    my ($op, $v) = @_;
    $op eq '=' || $op eq '==' ? { '=', $v } :
    $op eq '!=' ? { '!=', $v } :
    $op eq '^=' ? { 'LIKE', "$v%" } :
    $op eq '!^' ? { 'NOT LIKE', "$v%" } :
    $op eq '~=' ? { 'LIKE', '%' . "$v%" } :
    $op eq '!~' ? { 'NOT LIKE', '%' . "$v%" } :
    $op eq '?' ? { '!=', undef } :
    $op eq '??' ? { '=', undef } :
    $op =~ /^>|>=|<|<=$/ ? { $op, $v } :
    die "Unknown search op '$op'";
}

# <search> ::= <condition> { ',' <condition> }
# <condition> ::=
#     <value> |
#     { <field name> | '*' } <op> <value> |
#     <field name> <suffix> |
#     { '!' | } <func name>(<atom>)
# <op> ::= '=' | '==' | '!=' | '^=' | '!^' | '~=' | '!~' | '>' | '<' | '>=' | '<='
# <suffix> = '?' | '??'
# <atom> = <number> | <identifier>
# Spaces are significant around values, but not around keys.
# Values without field name are searched in default fields.
# Values with '*' field name are searched in all fields.
# Different fields are AND'ed, multiple values of the same field are OR'ed.
sub get_mask {
    my ($self) = @_;
    my %mask;
    for my $q (@{$self->search}) {
        my ($k, $v, $op) = @$q;
        $self->{db_searches}->{$k} or push @{$mask{$k} ||= []}, regex_op($op, $v);
    }
    for my $v (@{$self->{search_defaults}}) {
        my $re = regex_op('~=', $v);
        for my $k (@{$self->{default_searches}}) {
            $self->{db_searches}->{$k} or push @{$mask{$k} ||= []}, $re;
        }
        @{$self->{default_searches}} or push @{$mask{''} ||= []}, $re;
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

sub _maybe_cast {
    my ($self, $field, $value) = @_;
    my $type = $self->{search_casts}->{$field};
    $type ? \[ "CAST(? AS $type)", $value ] : $value;
}

sub _prepare_value {
    my ($self, $field, $value, $op) = @_;
    $value = $self->{enums}->{$field}->{$value} // $value;
    if ($op) { my ($k, $v) = %{sql_op($op, $value)}; return { $k, $self->_maybe_cast($field, $v) }; };
    $self->_maybe_cast($field, $value);
}

sub make_where {
    my ($self) = @_;
    my @cond;

    my %result;
    for my $q (@{$self->search}) {
        my ($k, $v, $op) = @$q;
        my $f = $self->{db_searches}->{$k} or next;
        push @{$result{$f} //= []}, $self->_prepare_value($k, $v, $op);
    }
    push @cond, \%result if %result;

    my (@sq_list, @sq_unknown);
    for my $d (@{$self->{search_subqueries}}) {
        my ($name, $value, $negate) = @$d;
        my $sq = $self->{subqueries}->{$name}
            or push @sq_unknown, $name and next;
        _where_msg($sq, $value, $negate);
        # SQL::Abstract uses double reference to designate subquery.
        my $sql_sq = \[ $sq->{sq} => $self->_prepare_value($name, $value) ];
        push @sq_list, $negate ? { -not_bool => $sql_sq } : $sql_sq;
    }
    msg(1143, join ',', @sq_unknown) if @sq_unknown;
    push @cond, @sq_list;

    my %default_result;
    for my $v (@{$self->{search_defaults}}) {
        for my $k (@{$self->{default_searches}}) {
            my $f = $self->{db_searches}->{$k} or next;
            push @{$default_result{$f} //= []}, $self->_prepare_value($k, $v, '~=');
        }
    }
    push @cond, { -or => [ %default_result ] } if %default_result;

    @cond > 1 ? { -and => \@cond } : @cond ? $cond[0] : {};
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

sub default_searches {
    my ($self, $searches, %opts) = @_;
    if (!$opts{nodb}) {
        for (@$searches) {
            $self->{db_searches}->{$_} or croak "Unknown search: $_";
        }
    }
    push @{$self->{default_searches}}, @$searches;
}

sub define_casts {
    my ($self, $casts) = @_;
    for (keys %$casts) {
        $self->{db_searches}->{$_} or croak "Unknown search to cast: $_";
        $self->{search_casts}->{$_} and croak "Duplicate cast: $_";
        $self->{search_casts}->{$_} = $casts->{$_};
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
    } grep $_->[0] eq $name, @{$self->search};
    $self->{search} = [ grep $_->[0] ne $name, @{$self->search} ];
    \@result;
}

sub search_subquery_value {
    my ($self, $name) = @_;
    $_->[0] eq $name and return $_->[1] for @{$self->{search_subqueries}};
    undef;
}

sub searches_subset_of {
    my ($self, $set) = @_;
    for (@{$self->search}, @{$self->{search_subqueries}}) {
        $set->{$_->[0]} or return 0;
    }
    1;
}

1;
