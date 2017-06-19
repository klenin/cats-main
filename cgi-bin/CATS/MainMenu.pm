package CATS::MainMenu;

use strict;
use warnings;

use CATS::Web qw(url_param);
use CATS::Misc qw($t);

sub selected_menu_item {
    my $default = shift || '';
    my $href = shift;

    my ($pf) = ($href =~ /[?;]f=([a-z_]+)/);
    $pf ||= '';
    #my $q = new CGI((split('\?', $href))[1]);

    my $page = url_param('f');
    #my $pf = $q->param('f') || '';

    (defined $page && $pf eq $page) ||
    (!defined $page && $pf eq $default);
}

sub mark_selected {
    my ($default, $menu) = @_;

    for my $i (@$menu) {
        if (selected_menu_item($default, $i->{href})) {
            $i->{selected} = 1;
            $i->{dropped} = 1;
        }

        my $submenu = $i->{submenu};
        for my $j (@$submenu) {
            if (selected_menu_item($default, $j->{href})) {
                $j->{selected} = 1;
                $i->{dropped} = 1;
            }
        }
    }
}

sub attach_menu {
   my ($menu_name, $default, $menu) = @_;
   mark_selected($default, $menu);

   $t->param($menu_name => $menu);
}

1;
