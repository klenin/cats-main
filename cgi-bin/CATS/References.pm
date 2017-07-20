package CATS::References;

use strict;
use warnings;

use CATS::Misc qw($is_root $t res_str url_f);

sub reference_names() {
    (
        { name => 'compilers', new => 542, item => 517 },
        { name => 'judges', new => 512, item => 511 },
        { name => 'keywords', new => 550, item => 549 },
        { name => 'import_sources', item => 557 },
        ($is_root ? { name => 'prizes', item => 565 } : ()),
    )
}

sub menu {
    my ($ref_name) = @_;

    my @result;
    for (reference_names()) {
        my $sel = $_->{name} eq $ref_name;
        push @result,
            { href => url_f($_->{name}), item => res_str($_->{item}), selected => $sel };
        if ($sel && $is_root && $_->{new}) {
            unshift @result,
                { href => url_f($_->{name}, new => 1), item => res_str($_->{new}) };
        }
        $t->param(title_suffix => res_str($_->{item})) if $sel;
    }
    @result;
}

1;
