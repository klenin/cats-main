package CATS::DeGrid;

use POSIX qw(ceil);

sub matrix {
    my ($data, $col_count) = @_;
    my $matrix = [];
    my $height = ceil(@$data / $col_count);
    my $i = 0;
    push @{$matrix->[$i++ % $height]}, $_ for @$data;
    $matrix;
}

sub calc_deletes_inserts {
    my ($all_items, $new_selection, $index_field, $selected_field) = @_;
    my (@deletes, @inserts);
    my %indexed = map { $_ => 1 } @$new_selection;

    for (@$all_items) {
        my $is_selected_now = exists $indexed{$_->{$index_field}};
        push @deletes, $_->{id} if $_->{$selected_field} && !$is_selected_now;
        push @inserts, $_->{id} if !$_->{$selected_field} && $is_selected_now;
        $_->{$selected_field} = $is_selected_now;
    }

    (\@deletes, \@inserts);
}

1;
