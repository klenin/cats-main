package CATS::UI::Wiki;

use strict;
use warnings;

use Encode;

use CATS::Constants;
use CATS::DB;
use CATS::Form;
use CATS::Globals qw($contest $is_jury $is_root $t $uid);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;
use CATS::Settings;
use CATS::TeX::Lite;

my $markdown;
BEGIN {
    $markdown = eval { require Text::MultiMarkdown; } ?
        sub { Text::MultiMarkdown::markdown($_[0]) } :
        sub { $_[0] }
}

sub _prepare_text {
    my ($text) = @_;
    $text = $markdown->($text);
    CATS::TeX::Lite::convert_all($text);
    $text;
}

my $str1_200 = CATS::Field::str_length(1, 200);
our $page_form = CATS::Form->new(
    table => 'wiki_pages',
    fields => [
        [ name => 'name', validators => [ $str1_200 ], caption => 601, ],
        [ name => 'is_public', validators => [ qr/^1?$/ ], caption => 669, before_save => sub { $_[0] // 0 } ],
    ],
    href_action => 'wiki_pages_edit',
    descr_field => 'name',
    template_var => 'wp',
    msg_deleted => 1073,
    msg_saved => 1074,
    before_display => sub {
        my ($fd, $p) = @_;
        my $ts = $fd->{texts} = $fd->{id} ? $dbh->selectall_hashref(q~
            SELECT id, lang, title FROM wiki_texts WHERE wiki_id = ?~, 'lang', undef,
            $fd->{id}) : {};
        for (@cats::langs) {
            my $r = $ts->{$_} //= {};
            $r->{href_edit} = url_f('wiki_edit', wiki_id => $fd->{id}, wiki_lang => $_, id => $r->{id});
            $r->{id} or next;
            $r->{href_delete} = url_f('wiki_pages_edit', id => $fd->{id}, delete => $r->{id});
            $r->{href_view} = url_f('wiki', name => $fd->{indexed}->{name}->{value}, lang => $_);
        }
        $t->param(submenu => [ CATS::References::menu('wiki_pages') ]);
    },
);

sub wiki_pages_frame {
    my ($p) = @_;
    $is_root or return;

    init_template($p, 'wiki_pages.html.tt');
    my $lv = CATS::ListView->new(web => $p, name => 'wiki_pages');

    $is_root and $page_form->delete_or_saved($p);

    $lv->define_columns(url_f('wiki_pages'), 0, 0, [
        { caption => res_str(601), order_by => 'name', width => '30%' },
        { caption => res_str(669), order_by => 'is_public', width => '5%' },
    ]);
    $lv->define_db_searches($page_form->{sql_fields});

    my ($q, @bind) = $sql->select('wiki_pages', [ 'id', @{$page_form->{sql_fields}} ], $lv->where);
    my $c = $dbh->prepare("$q " . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            ($is_root ? (
                href_text => url_f('wiki', name => $row->{name}),
                href_edit => url_f('wiki_pages_edit', id => $row->{id}),
                href_delete => url_f('wiki_pages', 'delete' => $row->{id})) : ()),
        );
    };
    $lv->attach(url_f('wiki_pages'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('wiki_pages') ]);
}

our $text_form = CATS::Form->new(
    table => 'wiki_texts',
    fields => [
        [ name => 'wiki_id', validators => [ $CATS::Fields::foreign_key ], ],
        [ name => 'wiki_lang', db_name => 'lang', validators => [ qr/^([a-z]{2})?$/ ], ],
        [ name => 'title', validators => [ $str1_200 ], caption => 601 ],
        [ name => 'text', caption => 677 ],
        [ name => 'author_id' ],
        [ name => 'last_modified', before_save => sub { \'CURRENT_TIMESTAMP' } ],
    ],
    href_action => 'wiki_edit',
    descr_field => 'title',
    template_var => 'wt',
    msg_deleted => 1073,
    msg_saved => 1074,
    after_make => sub {
        my ($form_data, $p) = @_;
        $form_data->{indexed}->{$_}->{value} = $p->{$_} for qw(wiki_id wiki_lang);
    },
    before_save => sub {
        my ($form_data, $p) = @_;
        my $wt = $form_data->{indexed};
        $wt->{author_id}->{value} = $uid;
    },
    before_display => sub {
        my ($form_data, $p) = @_;
        my $wt = $form_data->{indexed};
        $form_data->{author} = $wt->{author_id} && $dbh->selectrow_array(q~
            SELECT team_name FROM accounts WHERE id = ?~, undef,
            $wt->{author_id}->{value});
        my $pn = $form_data->{page_name} = Encode::decode_utf8($dbh->selectrow_array(q~
            SELECT name FROM wiki_pages WHERE id = ?~, undef,
            $wt->{wiki_id}->{value}));
        $wt->{last_modified}->{value} ||= $form_data->{id} && $dbh->selectrow_array(q~
            SELECT last_modified FROM wiki_texts WHERE id = ?~, undef,
            $form_data->{id});
        $form_data->{markdown} = _prepare_text($wt->{text}->{value});
        $t->param(
            title_suffix => $pn,
            problem_title => $pn,
            href_view => url_f('wiki', name => $pn),
            href_page => url_f('wiki_pages_edit', id => $wt->{wiki_id}->{value}),
            submenu => [ CATS::References::menu('wiki_pages') ],
        );
    },
);

sub wiki_pages_edit_frame {
    my ($p) = @_;
    $is_root or return;
    init_template($p, 'wiki_pages_edit.html.tt');
    $text_form->delete_or_saved($p);
    $page_form->edit_frame($p, redirect => [ 'wiki_pages' ]);
}

sub wiki_edit_frame {
    my ($p) = @_;
    $is_root && $p->{wiki_id} or return $p->redirect(url_f 'contests');
    init_template($p, 'wiki_edit.html.tt');
    $text_form->edit_frame($p, redirect_cancel => [ 'wiki_pages_edit', id => $p->{wiki_id} ]);
}

sub _choose_lang {
    my ($langs) = @_;
    for my $lng (CATS::Settings::lang, @cats::langs) {
        my @found = grep $lng eq $_->{lang}, @$langs;
        return $found[0] if @found;

    }
    $langs->[0];
}

sub wiki_frame {
    my ($p) = @_;
    init_template($p, 'wiki.html.tt');

    $p->{name} or return;
    my ($id, $is_public) = $dbh->selectrow_array(q~
        SELECT id, is_public FROM wiki_pages WHERE name = ?~, undef,
        $p->{name});
    $id && ($is_public || $is_root) or return;
    my $langs = $dbh->selectall_arrayref(q~
        SELECT id, lang FROM wiki_texts WHERE wiki_id = ?~, { Slice => {} },
        $id);
    @$langs or return;
    my $chosen_lang = _choose_lang($langs);
    my $page = $dbh->selectrow_hashref(q~
        SELECT title, text FROM wiki_texts WHERE id = ?~, undef,
        $chosen_lang->{id});
    $page->{name} = $p->{name};
    $page->{markdown} = _prepare_text($page->{text});
    delete $contest->{title};
    $t->param(
        page => $page,
        title_suffix => $page->{title},
        submenu => [
            ($is_root ? {
                href => url_f('wiki_edit',
                    wiki_id => $id, id => $chosen_lang->{id}, wiki_lang => $chosen_lang->{lang}),
                item => res_str(509, $p->{name}) } : ()),
        ],
    );
}

1;
