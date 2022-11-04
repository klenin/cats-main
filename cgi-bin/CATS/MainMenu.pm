package CATS::MainMenu;

use strict;
use warnings;

use CATS::Globals qw($contest $is_jury $sid $t $uid $user);
use CATS::Messages qw(res_str);
use CATS::Output qw(url_f);
use CATS::Utils qw(url_function);

sub new {
    my ($class, $data) = @_;
    bless $data, $class;
}

sub _selected_menu_item {
    my ($self, $default, $href) = @_;

    my ($pf) = ($href =~ /(?:[?;]f=|^)([a-z_]+)/);
    $pf ||= '';

    (defined $self->{f} && $pf eq $self->{f}) ||
    (!defined $self->{f} && defined $default && $pf eq $default);
}

sub _mark_selected {
    my ($self, $default, $menu) = @_;

    for my $i (@$menu) {
        if ($self->_selected_menu_item($default, $i->{href})) {
            $i->{selected} = 1;
            $i->{dropped} = 1;
        }

        my $submenu = $i->{submenu};
        for my $j (@$submenu) {
            if ($self->_selected_menu_item($default, $j->{href})) {
                $j->{selected} = 1;
                $i->{dropped} = 1;
            }
        }
    }
}

sub _attach_menu {
   my ($self, $menu_name, $default, $menu) = @_;
   $self->_mark_selected($default, $menu);

   $t->param($menu_name => $menu);
}

sub generate {
    my ($self) = @_;
    my $logged_on = $sid ne '';

    my @left_menu = (
        { item => $logged_on ? res_str(503) : res_str(500),
          href => $logged_on ? url_function('logout', sid => $sid) : url_function('login') },
        { item => res_str(502), href => url_f('contests') },
        { item => res_str(525), href => url_f('problems') },
        ($is_jury || !$contest->is_practice ? { item => res_str(526), href => url_f('users') } : ()),
        ($is_jury || $user->{is_site_org} || $contest->{show_sites} ?
            { item => res_str(513), href => url_f('contest_sites') } : ()),
        { item => res_str(510),
          href => url_f('console', $is_jury ? () : (uf => $uid || $user->{anonymous_id})) },
        ($is_jury ? { item => res_str(593), href => url_f('jobs') } : ()),
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

    if ($uid && ($self->{f} // '') ne 'logout') {
        @right_menu = ( { item => res_str(518), href => url_f('profile') } );
    }

    push @right_menu, (
        { item => res_str(544), href => url_f('about') },
        { item => res_str(406), href => url_f('problems_all') },
        { item => res_str(501), href => url_f('registration') } );

    $t->param(href_header_about => url_f('about'));
    $self->_attach_menu('left_menu', undef, \@left_menu);
    $self->_attach_menu('right_menu', 'about', \@right_menu);
}

1;
