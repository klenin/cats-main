package CATS::Template;

use strict;
use warnings;

use Template;
use CATS::Template::Filter;

my $tt;

sub new {
    my ($class, $file_name, $cats_dir) = @_;
    my $templates_path = "${cats_dir}../tt";

    $tt ||= Template->new({
        INCLUDE_PATH => $templates_path,
        COMPILE_EXT => '.ttc',
        COMPILE_DIR => "$templates_path/cache/",
        ENCODING => 'utf8',
        PLUGINS => {
            Javascript => 'CATS::Template::Plugin::Javascript'
        },
        FILTERS => {
            quote_controls => \&CATS::Template::Filter::quote_controls_filter,
            html_highlight_regions => [ \&CATS::Template::Filter::html_highlight_regions_filter, 2 ],
            linkify => \&CATS::Template::Filter::linkify,
            group_digits => \&CATS::Template::Filter::group_digits,
        }
    }) || die $Template::ERROR;

    my $self = { vars => {}, file_name => $file_name };
    bless $self, $class;

    return $self;
}

sub param {
    my $self = shift;
    if (@_ == 1) {
        my $arg = shift;
        if (ref($_[0]) eq 'HASH') {
            @{$self->{vars}}{keys %$arg} = @{$arg}{keys %$arg};
        }
        else {
            return $self->{vars}->{$arg};
        }
    }
    else {
        my %args = @_;
        @{$self->{vars}}{keys %args} = @args{keys %args};
    }
    $self;
}

sub output {
    my $self = shift;
    $tt->process($self->{file_name}, $self->{vars}, \my $res)
        or die $tt->error();
    $res;
}

1;
