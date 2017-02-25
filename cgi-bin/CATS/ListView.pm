package CATS::ListView;

use strict;
use warnings;

use Encode ();
use List::Util qw(first min max);

use CATS::Misc qw(
    $is_root
    $t
    $settings
    init_template
);
use CATS::Web qw(param url_param);

# Optimization: limit datasets by both maximum row count and maximum visible pages.
my $max_fetch_row_count = 1000;
my $visible_pages = 5;
my @display_rows = (10, 20, 30, 40, 50, 100, 300);

sub new {
    my ($class, %p) = @_;
    my $self = {
        name => $p{name} || die,
        template => $p{template} || die,
        array_name => $p{array_name} || $p{name},
        col_defs => undef,
        search => [],
        db_searches => {},
    };
    bless $self, $class;
    $self->init_params;
    init_template($self->{template}, $p{extra});
    $self;
}

sub settings { $settings->{$_[0]->{name}} }

sub init_params {
    my ($self) = @_;

    $_ && ref $_ eq 'HASH' or $_ = {} for $settings->{$self->{name}};
    my $s = $self->settings;
    $s->{search} ||= '';

    $s->{page} = url_param('page') if defined url_param('page');

    if (defined(my $search = Encode::decode_utf8 param('search'))) {
        if ($s->{search} ne $search) {
            $s->{search} = $search;
            $s->{page} = 0;
        }
    }
    $self->{search} = [ map [ /^(.*)=(.*)$/ ? ($1, $2) : ('', $_) ], split ',', $s->{search} ];

    if (defined url_param('sort')) {
        $s->{sort_by} = int(url_param('sort'));
        $s->{page} = 0;
    }

    if (defined url_param('sort_dir')) {
        $s->{sort_dir} = int(url_param('sort_dir'));
        $s->{page} = 0;
    }

    $s->{rows} ||= $display_rows[0];
    my $rows = param('rows') || 0;
    if ($rows > 0) {
        $s->{page} = 0 if $s->{rows} != $rows;
        $s->{rows} = $rows;
    }
}

sub attach {
    my ($self, $url, $fetch_row, $sth, $p) = @_;

    my $s = $settings->{$self->{name}} ||= {};

    my ($row_count, $page_count, @data) = (0, 0);
    my $page = \$s->{page};
    $$page ||= 0;
    my $rows = $s->{rows} || 1;

    # <search> = <condition> { ',' <condition> }
    # <condition> = <value> | <field name> '=' <value>
    # Values without field name are searched in all fields.
    # Different fields are AND'ed, multiple values of the same field are OR'ed.
    my %mask;
    for my $q (@{$self->{search}}) {
        my ($k, $v) = @$q;
        $self->{db_searches}->{$k} or push @{$mask{$k} ||= []}, $v;
    }
    for (values %mask) {
        my $s = join '|', map "\Q$_\E", @$_;
        $_ = qr/$s/i;
    }

    my $row_keys;
    ROWS: while (my %row = $fetch_row->($sth)) {
        $row_keys //= [ sort grep !$self->{db_searches}->{$_} && !/^href_/, keys %row ];
        last if $row_count > $max_fetch_row_count || $page_count > $$page + $visible_pages;
        for my $key (keys %mask) {
            defined first { Encode::decode_utf8($_ // '') =~ $mask{$key} }
                ($key ? ($row{$key}) : values %row)
                or next ROWS;
        }
        ++$row_count;
        $page_count = int(($row_count + $rows - 1) / $rows);
        next if $page_count > $$page + 1;
        # Remember the last visible page data in case of a too large requested page number.
        @data = () if @data == $rows;
        push @data, \%row;
    }

    $$page = min(max($page_count - 1, 0), $$page);
    my $range_start = max($$page - int($visible_pages / 2), 0);
    my $range_end = min($range_start + $visible_pages - 1, $page_count - 1);

    my $pp = $p->{page_params} || {};
    my $page_extra_params = join '', map ";$_=$pp->{$_}", keys %$pp;
    my $href_page = sub { "$url$page_extra_params;page=$_[0]" };
    my @pages = map {{
        page_number => $_ + 1,
        href_page => $href_page->($_),
        current_page => $_ == $$page
    }} $range_start..$range_end;

    $t->param(
        page => $$page, pages => \@pages, search => $s->{search},
        ($range_start > 0 ? (href_prev_pages => $href_page->($range_start - 1)) : ()),
        ($range_end < $page_count - 1 ? (href_next_pages => $href_page->($range_end + 1)) : ()),
        display_rows =>
            [ map { value => $_, text => $_, selected => $s->{rows} == $_ }, @display_rows ],
        $self->{array_name} => \@data,
    );
    if ($is_root) {
        my @s = (map([ $_, 0 ], sort keys %{$self->{db_searches}}), map [ $_, 1 ], @$row_keys);
        my $col_count = 4;
        my $row_count = int((@s + $col_count - 1) / $col_count);
        my $rows;
        my $i = 0;
        push @{$rows->[$i++ % $row_count]}, $_ for @s;
        $t->param(search_hints => $rows);
    }

    # Suppose that attach_listview call comes last, so we modify settings in-place.
    defined $s->{$_} && $s->{$_} ne '' or delete $s->{$_} for keys %$s;
}

sub check_sortable_field {
    my ($self, $s) = @_;
    return defined $s->{sort_by} && $s->{sort_by} =~ /^\d+$/ && $self->{col_defs}->[$s->{sort_by}]
}

sub order_by {
    my ($self) = @_;
    my $s = $self->settings;
    $self->check_sortable_field($s) or return '';
    sprintf 'ORDER BY %s %s',
        $self->{col_defs}->[$s->{sort_by}]{order_by}, ($s->{sort_dir} ? 'DESC' : 'ASC');
}

sub where { $_[0]->{where} ||= $_[0]->make_where }

sub make_where {
    my ($self) = @_;
    my %result;
    for my $q (@{$self->{search}}) {
        my ($k, $v) = @$q;
        my $f = $self->{db_searches}->{$k} or next;
        push @{$result{$f} //= []}, $v;
    }
    \%result;
}

sub where_cond {
    my ($self) = @_;
    my $w = $self->where;
    join ' AND ', map @{$w->{$_}} > 1 ? "$_ IN (" . join(', ', '?' x @{$w->{$_}}) . ')' : "$_ = ?",
        sort keys %$w;
}

sub maybe_where_cond {
    my ($self) = @_;
    my $w = $self->where;
    %{$self->where} ? ' AND ' . $self->where_cond : '';
}

sub where_params {
    my ($self) = @_;
    my $w = $self->where;
    map @{$w->{$_}}, sort keys %$w;
}

sub sort_in_memory {
    my ($self, $data) = @_;
    my $s = $self->settings;
    $self->check_sortable_field($s) or return $data;
    my $order_by = $self->{col_defs}->[$s->{sort_by}]{order_by};
    my $cmp = $s->{sort_dir} ?
        sub { $a->{$order_by} cmp $b->{$order_by} } :
        sub { $b->{$order_by} cmp $a->{$order_by} };
    [ sort $cmp @$data ];
}

sub define_db_searches {
    my ($self, $db_searches) = @_;
    if (ref $db_searches eq 'ARRAY') {
        for (@$db_searches) {
            $self->{db_searches}->{m/\.(.+)$/ ? $1 : $_} = $_;
        }
    }
    elsif (ref $db_searches eq 'HASH') {
        for (keys %$db_searches) {
            $self->{db_searches}->{$_} and die;
            $self->{db_searches}->{$_} = $db_searches->{$_};
        }
    }
    else {
        die;
    }
}

sub define_columns {
    my ($self, $url, $default_by, $default_dir, $col_defs) = @_;

    my $s = $self->settings;
    $s->{sort_by} = $default_by if !defined $s->{sort_by} || $s->{sort_by} eq '';
    $s->{sort_dir} = $default_dir if !defined $s->{sort_dir} || $s->{sort_dir} eq '';

    $self->{col_defs} = $col_defs;
    for my $i (0 .. $#$col_defs) {
        my $def = $col_defs->[$i];
        my $dir = 0;
        if ($s->{sort_by} eq $i) {
            $def->{'sort_' . ($s->{sort_dir} ? 'down' : 'up')} = 1;
            $dir = 1 - $s->{sort_dir};
        }
        $def->{href_sort} = "$url;sort=$i;sort_dir=$dir";
    }

    $t->param(col_defs => $col_defs);
}

1;
