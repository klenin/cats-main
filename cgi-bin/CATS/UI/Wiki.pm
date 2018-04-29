package CATS::UI::Wiki;

use strict;
use warnings;

use Encode;

use CATS::Constants;
use CATS::DB;
use CATS::Form;
use CATS::Globals qw($is_jury $is_root $t $uid);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(url_f);
use CATS::References;

sub page_fields() {qw(name is_public)}

my $page_form = CATS::Form->new({
    table => 'wiki_pages',
    fields => [ map +{ name => $_ }, page_fields() ],
    templates => { edit_frame => 'wiki_pages_edit.html.tt' },
    href_action => 'wiki_pages',
});

sub page_edit_frame {
    $page_form->edit_frame(sub {
        my ($w) = @_;
        my $ts = $w->{texts} = $w->{id} ? $dbh->selectall_hashref(q~
            SELECT id, lang, title FROM wiki_texts WHERE wiki_id = ?~, 'lang', undef,
            $w->{id}) : {};
        my @url = ('wiki_edit', wiki_id => $w->{id});
        $_->{href_edit} = url_f(@url, wiki_lang => $_->{lang}, id => $_->{id}) for values %$ts;
        $w->{href_add_text} = url_f(@url);
    });
}

sub page_edit_save {
    my ($p) = @_;
    $page_form->edit_save(sub {
        $_[0]->{is_public} //= 0;
    }) and msg(1074, Encode::decode_utf8($p->{name}))
}

sub wiki_pages_frame {
    my ($p) = @_;
    $is_root or return;

    defined $p->{edit} and return page_edit_frame;

    my $lv = CATS::ListView->new(name => 'wiki_pages', template => 'wiki_pages.html.tt');

    $is_root and $page_form->edit_delete(id => $p->{'delete'} // 0, descr => 'name', msg => 1073);
    $is_root && $p->{edit_save} and page_edit_save($p);

    $lv->define_columns(url_f('wiki_pages'), 0, 0, [
        { caption => res_str(601), order_by => 'name', width => '30%' },
        { caption => res_str(669), order_by => 'is_public', width => '5%' },
    ]);
    $lv->define_db_searches([ page_fields() ]);

    my ($q, @bind) = $sql->select('wiki_pages', [ 'id', page_fields() ], $lv->where);
    my $c = $dbh->prepare("$q " . $lv->order_by);
    $c->execute(@bind);

    my $fetch_record = sub {
        my $row = $_[0]->fetchrow_hashref or return ();
        return (
            %$row,
            ($is_root ? (
                href_edit => url_f('wiki_pages', edit => $row->{id}),
                href_delete => url_f('wiki_pages', 'delete' => $row->{id})) : ()),
        );
    };
    $lv->attach(url_f('wiki_pages'), $fetch_record, $c);

    $t->param(submenu => [ CATS::References::menu('wiki_pages') ]);
}

sub text_fields() {qw(wiki_id lang title text author_id last_modified)}

my $text_form = CATS::Form->new({
    table => 'wiki_texts',
    fields => [ map +{ name => $_ }, text_fields() ],
    templates => { edit_frame => 'wiki_edit.html.tt' },
    href_action => 'wiki_edit',
    edit_param => 'id',
});

sub text_edit_save {
    my ($p) = @_;
    $text_form->edit_save(sub {
        my ($t) = @_;
        $t->{lang} = $p->{wiki_lang};
        $t->{author_id} = $uid;
        $t->{last_modified} = \'CURRENT_TIMESTAMP';
    });
}

sub wiki_edit_frame {
    my ($p) = @_;
    $is_root or return;

    $p->{edit_cancel} and $p->redirect(url_f('wiki_pages', edit => $p->{wiki_id}));
    $p->{edit_save} and text_edit_save($p) and $p->{just_saved} = 1;

    $text_form->edit_frame(sub {
        my ($wt) = @_;
        $wt->{wiki_lang} //= $p->{wiki_lang};
        $wt->{wiki_id} //= $p->{wiki_id};
        delete $wt->{lang};
        $wt->{author} = $wt->{author_id} && $dbh->selectrow_array(q~
            SELECT team_name FROM accounts WHERE id = ?~, undef,
            $wt->{author_id});
        $wt->{page_name} = Encode::decode_utf8($dbh->selectrow_array(q~
            SELECT name FROM wiki_pages WHERE id = ?~, undef,
            $wt->{wiki_id}));
        $t->param(
            title_suffix => $wt->{page_name},
            problem_title => $wt->{page_name},
            submenu => [ CATS::References::menu('wiki_pages') ],
        );
        msg(1074, $wt->{page_name}) if $p->{just_saved};
    });
}

1;
