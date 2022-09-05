package CATS::UI::Wiki;

use strict;
use warnings;

use Encode;

use CATS::Constants;
use CATS::DB qw(:DEFAULT $db);
use CATS::Form;
use CATS::Globals qw($contest $is_jury $sid $t $uid $user);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::References;
use CATS::Settings;
use CATS::TeX::Lite;
use CATS::Utils;

my $markdown;
BEGIN {
    $markdown = eval { require Text::MultiMarkdown; } ?
        sub { Text::MultiMarkdown::markdown($_[0]) } :
        sub { $_[0] }
}

sub linkify_headers {
    my ($text) = @_;
    my $unicode_link_char = '&#128279;';
    $text =~ s~<h(\d+)([^>]*)id="([^"]+)"([^>]*)>([^<]*)</h\1>~
        <h$1$2id="$3"$4>$5<a class="wiki_header" href="#$3">$unicode_link_char</a></h$1>~gx;
    $text;
}

sub _prepare_text {
    my ($text) = @_;
    $text =~ s/(\]\(\?f=(:?.+))\)/$1;sid=$sid)/g if $sid;
    $text = $markdown->($text);
    CATS::TeX::Lite::convert_all($text);
    linkify_headers($text);
}

my $str1_200 = CATS::Field::str_length(1, 200);
our $page_form = CATS::Form->new(
    table => 'wiki_pages',
    fields => [
        [ name => 'name', validators => [ $str1_200 ], caption => 601, ],
        [ name => 'is_public', validators => $CATS::Field::bool, caption => 669,
             %CATS::Field::default_zero ],
    ],
    href_action => 'wiki_pages_edit',
    descr_field => 'name',
    template_var => 'wp',
    msg_deleted => 1073,
    msg_saved => 1074,
    validators => [ CATS::Field::unique('name') ],
    before_display => sub {
        my ($fd, $p) = @_;
        $fd->{href_public} = CATS::Utils::url_function('wiki', name => $fd->{indexed}->{name}->{value} || 'xx', lang => 'xx');

        my $ts = $fd->{texts} = $fd->{id} ? $dbh->selectall_hashref(q~
            SELECT id, lang, title, last_modified, OCTET_LENGTH(text) AS text_length
            FROM wiki_texts WHERE wiki_id = ?~, 'lang', undef,
            $fd->{id}) : {};
        for (@cats::langs) {
            my $r = $ts->{$_} //= {};
            $r->{href_edit} = url_f('wiki_edit', wiki_id => $fd->{id}, wiki_lang => $_, id => $r->{id});
            $r->{id} or next;
            $r->{href_delete} = url_f('wiki_pages_edit', id => $fd->{id}, delete => $r->{id});
            $r->{href_view} = url_f('wiki', name => $fd->{indexed}->{name}->{value}, lang => $_);
            $r->{last_modified} = $db->format_date($r->{last_modified});
        }
        $t->param(submenu => [ CATS::References::menu('wiki_pages') ]);
    },
);

sub _search_per_lang {
    my ($field) = @_;
    map { +"${field}_$_" => qq~(
        SELECT WT.text FROM wiki_texts WT WHERE WT.wiki_id = WP.id AND WT.lang = '$_')~ } @cats::langs;
}

sub wiki_pages_frame {
    my ($p) = @_;
    $user->privs->{edit_wiki} or return;

    init_template($p, 'wiki_pages');
    my $lv = CATS::ListView->new(web => $p, name => 'wiki_pages', url => url_f('wiki_pages'));

    $user->privs->{edit_wiki} and $page_form->delete_or_saved($p);

    $lv->default_sort(0)->define_columns([
        { caption => res_str(601), order_by => 'name', width => '30%' },
        { caption => res_str(669), order_by => 'is_public', width => '5%', col => 'Pb' },
        { caption => res_str(672), order_by => 'langs', width => '5%', col => 'Ls' },
        { caption => res_str(645), order_by => 'contest_count', width => '5%', col => 'Ct' },
        { caption => res_str(684), order_by => 'total_size', width => '5%', col => 'Sz' },
        { caption => res_str(634), order_by => 'last_modified', width => '5%', col => 'Lm' },
    ]);
    $lv->define_db_searches($page_form->{sql_fields});
    $lv->define_db_searches({ _search_per_lang('text'), _search_per_lang('title') });
    $lv->default_searches([ qw(name) ]);

    my ($q, @bind) = $sql->select('wiki_pages WP', [
        'WP.id', @{$page_form->{sql_fields}},
        ($lv->visible_cols->{Ls} ? q~(
            SELECT LIST(WT.lang) FROM wiki_texts WT
            WHERE WT.wiki_id = WP.id) AS langs~ : ()),
        ($lv->visible_cols->{Ct} ? q~(
            SELECT COUNT(*) FROM contest_wikis CW
            WHERE CW.wiki_id = WP.id) AS contest_count~ : ()),
        ($lv->visible_cols->{Sz} ? q~(
            SELECT SUM(OCTET_LENGTH(WT.text)) FROM wiki_texts WT
            WHERE WT.wiki_id = WP.id) AS total_size~ : ()),
        ($lv->visible_cols->{Sz} ? q~(
            SELECT MAX(WT.last_modified) FROM wiki_texts WT
            WHERE WT.wiki_id = WP.id) AS last_modified~ : ()),
    ], $lv->where);
    my $sth = $dbh->prepare("$q " . $lv->order_by);
    $sth->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            ($user->privs->{edit_wiki} ? (
                href_text => url_f('wiki', name => $row->{name}),
                href_contests => url_f('contests', search => "has_wiki($row->{id})"),
                href_edit => url_f('wiki_pages_edit', id => $row->{id}),
                href_edit_langs => $row->{langs} && {
                    map { $_ => url_f('wiki_edit', wiki_id => $row->{id}, wiki_lang => $_) }
                        split ',', $row->{langs} },
                href_public => url_function('wiki', name => $row->{name}),
                href_delete => url_f('wiki_pages', 'delete' => $row->{id})) : ()),
        );
    };
    $lv->date_fields(qw(last_modified));
    $lv->attach($fetch_record, $sth);

    $t->param(submenu => [ CATS::References::menu('wiki_pages') ]);
}

our $text_form = CATS::Form->new(
    table => 'wiki_texts',
    fields => [
        [ name => 'wiki_id', validators => [ $CATS::Field::foreign_key ], ],
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
        $form_data->{author} = $wt->{author_id}->{value} && $dbh->selectrow_array(q~
            SELECT team_name FROM accounts WHERE id = ?~, undef,
            $wt->{author_id}->{value});
        my $pn = $form_data->{page_name} = Encode::decode_utf8($dbh->selectrow_array(q~
            SELECT name FROM wiki_pages WHERE id = ?~, undef,
            $wt->{wiki_id}->{value}));
        my $lm = $wt->{last_modified};
        $lm->{value} ||= $form_data->{id} && $dbh->selectrow_array(q~
            SELECT last_modified FROM wiki_texts WHERE id = ?~, undef,
            $form_data->{id});
        $lm->{value} = $db->format_date($lm->{value});
        $form_data->{markdown} = _prepare_text($wt->{text}->{value});
        $t->param(
            title_suffix => $pn,
            problem_title => $pn,
            href_view => url_f('wiki', name => $pn),
            href_public_view => $wt->{is_publc}->{value} && url_function('wiki', name => $pn),
            href_page => $user->privs->{edit_wiki} &&
                url_f('wiki_pages_edit', id => $wt->{wiki_id}->{value}),
            submenu => [ CATS::References::menu('wiki_pages') ],
        );
    },
    override_get_id => sub {
        my ($form, $p) = @_;
        $p->{$form->{id_param}} ||
        $p->{wiki_id} && $p->{wiki_lang} && $dbh->selectrow_array(q~
            SELECT id FROM wiki_texts WHERE wiki_id = ? AND lang = ?~, undef,
            $p->{wiki_id}, $p->{wiki_lang});
    },
);

sub wiki_pages_edit_frame {
    my ($p) = @_;
    $user->privs->{edit_wiki} or return;
    init_template($p, 'wiki_pages_edit.html.tt');
    $text_form->delete_or_saved($p);
    $page_form->edit_frame($p, redirect => [ 'wiki_pages' ]);
}

sub _can_edit {
    my ($wiki_id) = @_;
    $user->privs->{edit_wiki} || $is_jury && $dbh->selectrow_array(q~
        SELECT id FROM contest_wikis
        WHERE contest_id = ? AND wiki_id = ? AND allow_edit = 1~, undef,
        $contest->{id}, $wiki_id);
}

sub wiki_edit_frame {
    my ($p) = @_;
    $p->{wiki_id} && _can_edit($p->{wiki_id}) or return $p->redirect(url_f 'contests');
    init_template($p, 'wiki_edit.html.tt');
    my $s = $CATS::Settings::settings->{wiki_edit} //= {};
    $s->{rows} = $p->{settings_rows} if $p->{settings_rows};
    $s->{sync} = $p->{sync} if defined $p->{sync};
    $t->param(settings => $s);
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
    init_template($p, 'wiki');

    $p->{name} or return;
    my ($id, $is_public) = $dbh->selectrow_array(q~
        SELECT id, is_public FROM wiki_pages WHERE name = ?~, undef,
        $p->{name});
    $id && ($is_public || $user->privs->{edit_wiki}) or return;
    my $langs = $dbh->selectall_arrayref(q~
        SELECT id, lang FROM wiki_texts WHERE wiki_id = ?~, { Slice => {} },
        $id);
    @$langs or return $user->privs->{edit_wiki} && $p->redirect(url_f('wiki_edit',
        wiki_id => $id, wiki_lang => CATS::Settings::lang));
    my $chosen_lang = _choose_lang($langs);
    my $page = $dbh->selectrow_hashref(q~
        SELECT title, text FROM wiki_texts WHERE id = ?~, undef,
        $chosen_lang->{id});
    if ($page->{title} =~ /^\!(\w+)\s*(\w+)?/) {
        if ($1 eq 'redirect' && $2) {
            return $p->redirect(url_f('wiki', name => $2));
        }
    }
    $page->{name} = $p->{name};
    $page->{markdown} = _prepare_text($page->{text});
    delete $contest->{title};
    $t->param(
        page => $page,
        title_suffix => $page->{title},
        submenu => [
            (_can_edit($id) ? ({
                href => url_f('wiki_edit',
                    wiki_id => $id, id => $chosen_lang->{id}, wiki_lang => $chosen_lang->{lang}),
                item => res_str(509, $p->{name}) },
                ($is_public ?
                    { href => url_function('wiki', name => $p->{name}), item => res_str(400) } :
                    ()),
            ) : ()),
        ],
    );
}

1;
