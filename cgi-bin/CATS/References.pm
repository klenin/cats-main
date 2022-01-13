package CATS::References;

use strict;
use warnings;

use CATS::Globals qw($is_jury $t $user);
use CATS::Messages qw(res_str);
use CATS::Output qw(url_f);

sub new_if_root { $user->is_root ? (new => $_[0]) : () }

sub reference_names() {
    (
        { name => 'compilers', new_if_root(542), item => 517 },
        { name => 'judges', new_if_root(512), item => 511 },
        { name => 'keywords', new_if_root(550), item => 549 },
        { name => 'import_sources', item => 557 },
        ($user->is_root ? { name => 'prizes', item => 565 } : ()),
        ($user->is_root ? { name => 'contact_types', new => 587, item => 586 } : ()),
        ($user->privs->{edit_wiki} ? { name => 'wiki_pages', new => 590, item => 589 } : ()),
        ($is_jury ? { name => 'snippets', new_if_root(592), item => 591 } : ()),
        ($user->privs->{edit_sites} ? { name => 'sites', new => 514, item => 513 } : ()),
        ($user->is_root ? { name => 'account_tokens', item => 516 } : ()),
        ($is_jury ? { name => 'contest_tags', new_if_root(405), item => 404 } : ()),
        ($is_jury ? { name => 'de_tags', new_if_root(403), item => 402 } : ()),
        ($user->is_root ? { name => 'files', new => 401, item => 570 } : ()),
        { name => 'acc_groups', new_if_root(409), item => 410 },
        { name => 'awards', ($is_jury ? (new => 412) : ()), item => 413 },
    )
}

sub menu {
    my ($ref_name) = @_;

    my @result;
    for (reference_names()) {
        my $sel = $_->{name} eq $ref_name;
        $_->{item} or die $_->{name};
        push @result,
            { href => url_f($_->{name}), item => res_str($_->{item}), selected => $sel };
        if ($sel && $_->{new}) {
            unshift @result,
                { href => url_f($_->{name} . '_edit'), item => res_str($_->{new}), new => 1 };
        }
        $t->param(title_suffix => res_str($_->{item})) if $sel;
    }
    @result;
}

1;
