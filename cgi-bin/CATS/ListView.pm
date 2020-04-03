package CATS::ListView;

use strict;
use warnings;

use Encode ();
use List::Util qw(first min max);

use CATS::DB;
use CATS::Globals qw($is_jury $t);
use CATS::Messages qw(msg);
use CATS::RouteParser;
use CATS::QueryBuilder;
use CATS::Settings qw($settings);
use CATS::Utils;

my $visible_pages = 5;
my @display_rows = (10, 20, 30, 40, 50, 100, 200, 300);

# Params:
# name -- settings name, pass empty string to ignore settings,
# template, array_name, extra, extra_settings.
sub new {
    my ($class, %p) = @_;
    my $self = {
        web => $p{web} || die,
        name => $p{name} // die,
        array_name => $p{array_name} || $p{name},
        col_defs => undef,
        extra_settings => $p{extra_settings} || {},
        qb => CATS::QueryBuilder->new,
        url => $p{url},
        template => $p{template} // $t,
        settings => {},
        visible_cols => {},
    };
    if ($settings && $p{name}) {
        $_ && ref $_ eq 'HASH' or $_ = {} for $settings->{$p{name}};
        $self->{settings} = $settings->{$p{name}};
    }
    bless $self, $class;
    $self->init_params;
    $self;
}

sub settings { $_[0]->{settings} }
sub visible_cols { $_[0]->{visible_cols} }
sub qb { $_[0]->{qb} }
sub submitted { $_[0]->{submitted} }
sub url { $_[0]->{url} }

my $route = [ 1,
    page => integer, search => undef, sort => qr/^[0-9a-zA-Z]+$/, sort_dir => integer,
    submitted => bool, rows => integer, cols => array_of ident, ];

sub init_params {
    my ($self) = @_;

    my $s = $self->settings;
    $s->{search} ||= '';

    my $w = $self->{web};
    CATS::RouteParser::parse_route($w, $route);

    $s->{page} = $w->{page} if defined $w->{page};

    if (defined(my $search = Encode::decode_utf8 $w->{search})) {
        if ($s->{search} ne $search) {
            $s->{search} = $search;
            $s->{page} = 0;
        }
    }
    $self->qb->parse_search($s->{search});

    if (defined $w->{sort}) {
        $s->{sort_by} = /^\d+$/ ? int($_) : $_ for $w->{sort};
        $s->{page} = 0;
    }

    if (defined $w->{sort_dir}) {
        $s->{sort_dir} = int($w->{sort_dir});
        $s->{page} = 0;
    }

    $self->{submitted} = $w->{submitted} ? 1 : 0;

    $self->{cols} =
        !$is_jury ? undef :
        # Has user just opened page or deselected all columns?
        $self->{submitted} || @{$w->{cols}} ? $w->{cols} :
        !defined $s->{cols} ? undef :
        $s->{cols} eq '-' ? [] :
        [ split ',', $s->{cols} ];

    if (my %es = %{$self->{extra_settings}}) {
        CATS::RouteParser::parse_route($w, [ 1, %es ]);
        $s->{$_} = $w->{$_} for grep defined $w->{$_}, keys %es;
    }

    $s->{rows} ||= $display_rows[1];
    my $rows = $w->{rows} || 0;
    if ($rows > 0) {
        $s->{page} = 0 if $s->{rows} != $rows;
        $s->{rows} = $rows;
    }
}

sub _subquery_msg_raw {
    my ($sq) = @_;
    $sq->{m} or return;
    my $r = CATS::Messages::res_str_lang_raw(CATS::Settings::lang, $sq->{m});
    $r =~ s/%[a-z]/?/g;
    $r;
}

sub _search_hints {
    my ($self, $row_keys) = @_;
    $is_jury or return;
    $row_keys ||= [];
    my $sqs = $self->qb->{subqueries};
    my @s = (
        map([ $_, 0 ], sort keys %{$self->qb->{db_searches}}),
        map([ $_, 1 ], grep !$self->qb->{db_searches}->{$_}, @$row_keys),
        map([ $_, 2, _subquery_msg_raw($sqs->{$_}) ], sort keys %$sqs),
    );
    my $col_count = 4;
    my $row_count = int((@s + $col_count - 1) / $col_count);
    my $rows;
    for my $i (0 .. $row_count - 1) {
        for my $j (0 .. $col_count - 1) {
            push @{$rows->[$i]}, $s[$j * $row_count + $i];
        }
    }
    (
        search_hints => $rows,
        search_enums => $self->qb->{enums},
    );
}

sub common_param {
    my ($self, $row_keys) = @_;
    (
        search => $self->settings->{search},
        display_rows => [
            map { value => $_, text => $_, selected => $self->settings->{rows} == $_ }, @display_rows ],
        lv_settings => $self->settings,
        $self->_search_hints($row_keys),
    );
}

sub attach {
    my ($self, $fetch_row, $sth, $p) = @_;
    $self->{url} or die;

    my ($row_count, $fetch_count, $page_count, @data) = (0, 0, 0);
    my $range = { first_row => 0, last_row => 0 };
    my $page = \$self->settings->{page};
    $$page ||= 0;
    my $rows = $self->settings->{rows} || 1;

    my %mask = %{$self->qb->get_mask};

    my $row_keys;
    ROWS: while (my %row = $fetch_row->($sth)) {
        if (!$row_keys) {
            if (my @unknown_searches = grep $_ && !exists $row{$_}, sort keys %mask) {
                delete $mask{$_} for @unknown_searches;
                msg(1143, join ', ', @unknown_searches);
            }
            $row_keys = [ sort grep !/^href_/, keys %row ];
        }
        msg(1166), last if ++$fetch_count > $CATS::Globals::max_fetch_row_count;
        last if $page_count > $$page + $visible_pages;
        for my $key (keys %mask) {
            defined first { ($_ // '') =~ $mask{$key} }
                @row{$key ? $key : @$row_keys}
                or next ROWS;
        }
        ++$row_count;
        $page_count = int(($row_count + $rows - 1) / $rows);
        next if $page_count > $$page + 1;
        # Remember the last visible page data in case of a too large requested page number.
        @data = () if @data == $rows;
        $range->{first_row} = $row_count if !@data;
        $range->{last_row} = $row_count;
        push @data, \%row;
    }

    $$page = min(max($page_count - 1, 0), $$page);
    my $range_start = max($$page - int($visible_pages / 2), 0);
    my $range_end = min($range_start + $visible_pages - 1, $page_count - 1);

    my $pp = $p->{page_params} || {};
    my $page_extra_params = join '', map ";$_=" . CATS::Utils::escape_url($pp->{$_}),
        grep defined $pp->{$_}, sort keys %$pp;
    my $href_page = sub { "$self->{url}$page_extra_params;page=$_[0]" };
    my @pages = map {{
        page_number => $_ + 1,
        href_page => $href_page->($_),
        current_page => $_ == $$page
    }} $range_start..$range_end;
    if ($page_extra_params) {
        $_->{href_sort} .= $page_extra_params for @{$self->{col_defs}};
    }

    $self->{visible_data} = \@data;
    $self->{template}->param(
        $self->common_param($row_keys),
        page => $$page, pages => \@pages,
        href_lv_action => $self->{url} . $page_extra_params,
        ($range_start > 0 ? (href_prev_pages => $href_page->($range_start - 1)) : ()),
        ($range_end < $page_count - 1 ? (href_next_pages => $href_page->($range_end + 1)) : ()),
        $self->{array_name} => \@data,
        lv_array_name => $self->{array_name},
        lv_range => $range,
    );

    # Suppose that attach call comes last, so we modify settings in-place.
    my $s = $self->settings;
    defined $s->{$_} && $s->{$_} ne '' or delete $s->{$_} for keys %$s;
}

sub visible_data { $_[0]->{visible_data} }
sub total_row_count { scalar @{$_[0]->{visible_data}} }

sub find_sorting_col {
    my ($self, $s) = @_;
    return defined $_ && (/^\d+$/ ? $self->{col_defs}->[$_] : $self->{col_defs_idx}->{$_})
        for $s->{sort_by};
}

sub order_by {
    my ($self) = @_;
    my $s = $self->settings;
    my $c = $self->find_sorting_col($s) or return '';
    sprintf 'ORDER BY %s %s', $c->{order_by}, ($s->{sort_dir} ? 'DESC' : 'ASC');
}

sub where { $_[0]->{where} ||= $_[0]->make_where }

sub make_where { $_[0]->qb->make_where }

sub where_cond {
    my ($self) = @_;
    my $where = $sql->where($self->where);
    $where =~ s/^\s*WHERE\s*//;
    $where;
}

sub maybe_where_cond {
    my ($self) = @_;
    %{$self->where} ? ' AND ' . $self->where_cond : '';
}

sub where_params {
    my ($self) = @_;
    my (undef, @params) = $sql->where($self->where);
    @params;
}

sub sort_in_memory {
    my ($self, $data) = @_;
    my $s = $self->settings;
    my $col_def = $self->find_sorting_col($s) or return $data;
    my $order_by = $col_def->{order_by};
    my $cmp =
        $col_def->{numeric} ?
            ($s->{sort_dir} ?
                sub { $a->{$order_by} <=> $b->{$order_by} } :
                sub { $b->{$order_by} <=> $a->{$order_by} }) :
            ($s->{sort_dir} ?
                sub { $a->{$order_by} cmp $b->{$order_by} } :
                sub { $b->{$order_by} cmp $a->{$order_by} });
    [ sort $cmp @$data ];
}

sub define_db_searches { $_[0]->qb->define_db_searches($_[1]) }
sub define_subqueries { $_[0]->qb->define_subqueries($_[1]) }
sub define_enums { $_[0]->qb->define_enums($_[1]) }

sub default_sort {
    my ($self, $default_by, $default_dir) = @_;
    my $s = $self->settings;
    $s->{sort_by} = $default_by if !defined $s->{sort_by} || $s->{sort_by} eq '';
    $s->{sort_dir} = ($default_dir // 0) if !defined $s->{sort_dir} || $s->{sort_dir} eq '';
    $self;
}

sub define_columns {
    my ($self, $col_defs) = @_;

    my $s = $self->settings;

    $self->{url} or die;
    $self->{col_defs} = $col_defs or die;

    my $cd_idx = $self->{col_defs_idx} = {};
    $cd_idx->{$_->{col}} = $_ for grep $_->{col}, @$col_defs;

    my $init = defined $self->{cols} ? 0 : 1;
    $self->{visible_cols} = { map { $_->{col} => $init } grep $_->{col}, @$col_defs };
    if (!$init) {
        $self->{visible_cols}->{$_} = 1 for @{$self->{cols}};
    }

    for my $i (0 .. $#$col_defs) {
        my $def = $col_defs->[$i];
        $def->{visible} = !$def->{col} || $self->{visible_cols}->{$def->{col}} or next;
        my $dir = 0;
        if ($s->{sort_by} eq $i || $s->{sort_by} eq ($def->{col} // '')) {
            $def->{'sort_' . ($s->{sort_dir} ? 'down' : 'up')} = 1;
            $dir = 1 - $s->{sort_dir};
        }
        $def->{href_sort} = sprintf '%s;sort=%s;sort_dir=%s', $self->{url}, $def->{col} // $i, $dir;
    }
    if (grep !$_->{visible}, @$col_defs) {
        $s->{cols} = join(',', map { $_->{visible} && $_->{col} ? $_->{col} : () } @$col_defs) || '-';
    }
    else {
        delete $s->{cols};
    }

    $self->{template}->param(
        col_defs => $col_defs,
        can_change_cols => ($is_jury && scalar %{$self->{visible_cols}}),
        visible_cols => $self->{visible_cols});
}

1;
