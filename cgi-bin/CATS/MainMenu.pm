package CATS::MainMenu;

use strict;
use warnings;

use CATS::Misc qw($t $sid $contest $uid $is_jury $user res_str url_f get_anonymous_uid);
use CATS::Utils qw(url_function);
use CATS::Web qw(url_param);

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

sub generate_menu {
    my $logged_on = $sid ne '';

    my @left_menu = (
        { item => $logged_on ? res_str(503) : res_str(500),
          href => $logged_on ? url_function('logout', sid => $sid) : url_function('login') },
        { item => res_str(502), href => url_f('contests') },
        { item => res_str(525), href => url_f('problems') },
        ($is_jury || !$contest->is_practice ? { item => res_str(526), href => url_f('users') } : ()),
        ($is_jury ? { item => res_str(513), href => url_f('contest_sites') } : ()),
        { item => res_str(510),
          href => url_f('console', $is_jury ? () : (uf => $uid || get_anonymous_uid())) },
        ($is_jury ? () : { item => res_str(557), href => url_f('import_sources') }),
    );

    if ($is_jury) {
        push @left_menu, (
            { item => res_str(548), href => url_f('compilers') },
            { item => res_str(545), href => url_f('similarity') }
        );
    }
    else {
        push @left_menu, (
            { item => res_str(517), href => url_f('compilers') },
            { item => res_str(549), href => url_f('keywords') } );
    }

    unless ($contest->is_practice) {
        push @left_menu, ({
            item => res_str(529),
            href => url_f('rank_table', $is_jury ? () : (cache => 1, hide_virtual => !$user->{is_virtual}))
        });
    }

    my @right_menu = ();

    if ($uid && (url_param('f') ne 'logout')) {
        @right_menu = ( { item => res_str(518), href => url_f('profile') } );
    }

    push @right_menu, (
        { item => res_str(544), href => url_f('about') },
        { item => res_str(501), href => url_f('registration') } );

    attach_menu('left_menu', undef, \@left_menu);
    attach_menu('right_menu', 'about', \@right_menu);
}

1;
