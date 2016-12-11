package CATS::ListView;

use strict;
use warnings;

use Encode ();
use List::Util qw(first min max);

use CATS::Misc qw(
    $t
    $settings
    $listview_name
    init_template
);
use CATS::Web qw(param url_param);

use Exporter qw(import);
our @EXPORT = qw(
    init_listview_template
    attach_listview
    order_by
    sort_listview
    define_columns
    attach_listview
);

my ($listview_array_name, $col_defs);

# Optimization: limit datasets by both maximum row count and maximum visible pages.
my $max_fetch_row_count = 1000;
my $visible_pages = 5;
my @display_rows = (10, 20, 30, 40, 50, 100, 300);

sub init {
    $listview_array_name = '';
    $col_defs = '';
}

sub init_listview_params {
    $_ && ref $_ eq 'HASH' or $_ = {} for $settings->{$listview_name};
    my $s = $settings->{$listview_name};
    $s->{search} ||= '';

    $s->{page} = url_param('page') if defined url_param('page');

    my $search = Encode::decode_utf8(param('search'));
    if (defined $search){
        if ($s->{search} ne $search) {
            $s->{search} = $search;
            $s->{page} = 0;
        }
    }

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

sub init_listview_template {
    ($listview_name, $listview_array_name, my $file_name, my $p) = @_;
    init_listview_params;
    init_template($file_name, $p);
}

sub attach_listview {
    my ($url, $fetch_row, $sth, $p) = @_;
    $listview_name or die;
    my $s = $settings->{$listview_name};

    my ($row_count, $page_count, @data) = (0, 0);
    my $page = \$s->{page};
    $$page ||= 0;
    my $rows = $s->{rows} || 1;

    # <search> = <condition> { ',' <condition> }
    # <condition> = <value> | <field name> '=' <value>
    # Values without field name are searched in all fields.
    # Different fields are AND'ed, multiple values of the same field are OR'ed.
    my %mask;
    for my $q (split ',', $s->{search}) {
        my ($k, $v) = $q =~ /^(.*)=(.*)$/ ? ($1, $2) : ('', $q);
        push @{$mask{$k} ||= []}, $v;
    }
    for (values %mask) {
        my $s = join '|', map "\Q$_\E", @$_;
        $_ = qr/$s/i;
    }

    ROWS: while (my %row = $fetch_row->($sth)) {
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
        $listview_array_name => \@data,
    );
}

sub check_sortable_field {
    my ($s) = @_;
    return defined $s->{sort_by} && $s->{sort_by} =~ /^\d+$/ && $col_defs->[$s->{sort_by}]
}

sub order_by {
    my $s = $settings->{$listview_name};
    check_sortable_field($s) or return '';
    sprintf 'ORDER BY %s %s',
        $col_defs->[$s->{sort_by}]{order_by}, ($s->{sort_dir} ? 'DESC' : 'ASC');
}

sub sort_listview {
    my $data = shift;
    my $s = $settings->{$listview_name};
    check_sortable_field($s) or return $data;
    my $order_by = $col_defs->[$s->{sort_by}]{order_by};
    my $cmp = $s->{sort_dir} ?
        sub { $a->{$order_by} cmp $b->{$order_by} } :
        sub { $b->{$order_by} cmp $a->{$order_by} };
    [ sort $cmp @$data ];
}

sub define_columns {
    (my $url, my $default_by, my $default_dir, $col_defs) = @_;

    my $s = $settings->{$listview_name};
    $s->{sort_by} = $default_by if !defined $s->{sort_by} || $s->{sort_by} eq '';
    $s->{sort_dir} = $default_dir if !defined $s->{sort_dir} || $s->{sort_dir} eq '';

    for (my $i = 0; $i < @$col_defs; ++$i) {
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
