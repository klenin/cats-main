package CATS::UI::ProblemHistory;

use strict;
use warnings;

use Encode qw();

use CATS::DB;
use CATS::Globals qw($cid $is_jury $is_root $t $uid);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::Problem::Parser;
use CATS::Problem::Save;
use CATS::Problem::Storage;
use CATS::Problem::Utils;
use CATS::StaticPages;
use CATS::Utils qw(source_encodings);

sub _get_problem_info {
    my ($p) = @_;
    my $pr = $dbh->selectrow_hashref(q~
        SELECT CP.status, P.title, P.repo, P.contest_id, CA.is_jury, P.repo_path
        FROM contest_problems CP
        INNER JOIN problems P ON CP.problem_id = P.id
        LEFT JOIN contest_accounts CA ON CA.contest_id = P.contest_id AND CA.account_id = ?
        WHERE CP.contest_id = ? AND P.id = ?~, { Slice => {} },
        $uid // 0, $cid, $p->{pid});
    $pr->{is_jury} //= $is_root;
    $pr;
}

sub _problem_commitdiff {
    my ($p, $title, $sha, $se, $import_log, $new_name) = @_;

    my $pid = $p->{pid};
    init_template($p, 'problem_history_commit.html.tt');
    my $submenu = [
        { href => url_f('problem_details', pid => $pid), item => res_str(504) },
        { href => url_f('problem_history', pid => $pid), item => res_str(568) },
        { href => url_f('problem_history_tree', hb => $sha, pid => $pid), item => res_str(570) },
        { href => url_f('problem_git_package', pid => $pid, sha => $sha), item => res_str(569) },
        ($p->{file} ? ({
            href => url_f('problem_history_edit', file => $new_name || $p->{file}, pid => $pid, hb => $sha),
            item => res_str(572) }) : ()),
    ];
    $t->param(
        commit => CATS::Problem::Storage::show_commit($pid, $sha, $se),
        problem_title => $title,
        title_suffix => $title,
        submenu => $submenu,
        problem_import_log => $import_log,
        source_encodings => source_encodings($se),
    );
}

sub problem_history_commit_frame {
    my ($p) = @_;
    $is_jury or return;
    my $pr = _get_problem_info($p) or return $p->redirect(url_f 'contests');
    _problem_commitdiff($p, $pr->{title}, $p->{h}, $p->{src_enc} || 'WINDOWS-1251');
}

sub set_history_paths_urls {
    my ($pid, $paths) = @_;
    for (@$paths) {
        $_->{href} = url_f("problem_history_$_->{type}", file => $_->{name}, pid => $pid, hb => $_->{hash_base});
    }
}

sub set_submenu_for_tree_frame {
    my ($pid, $hash, @items) = @_;
    $t->param(submenu => [
        { href => url_f('problem_details', pid => $pid), item => res_str(504) },
        { href => url_f('problem_history', pid => $pid), item => res_str(568) },
        { href => url_f('problem_history_commit', pid => $pid, h => $hash), item => res_str(571) },
        { href => url_f('problem_git_package', pid => $pid, sha => $hash), item => res_str(569) },
        @items,
    ]);
}

sub is_allow_editing {
    my ($git_data, $hb) = @_;
    !$git_data->{is_remote} && !$git_data->{image} && $git_data->{latest_sha} eq $hb;
}

sub problem_history_tree_frame {
    my ($p) = @_;
    $is_jury or return;
    my $pr = _get_problem_info($p) or return $p->redirect(url_f 'contests');

    my $log;
    if ($p->{delete_file}) {
        (my $error, $log) = _delete_file($p, $pr) if $p->{delete_file};
        $error or return;
    }

    init_template($p, 'problem_history_tree.html.tt');

    my $tree = CATS::Problem::Storage::show_tree(
        $p->{pid}, $p->{hb}, $p->{file} || undef, $p->{repo_enc});
    for (@{$tree->{entries}}) {
        my %url_params = (file => $_->{name}, pid => $p->{pid}, hb => $p->{hb});
        if ($_->{type} eq 'blob') {
            $_->{href} = url_f('problem_history_blob', %url_params);
            $_->{href_raw} = url_f('problem_history_raw', %url_params);
            if ($pr->{is_jury} && is_allow_editing($tree, $p->{hb})) {
                $_->{href_edit} = url_f('problem_history_edit', %url_params);
                my %del_url = (delete_file => $_->{name}, pid => $p->{pid}, hb => $p->{hb});
                $_->{href_delete} = url_f('problem_history_tree', %del_url);
            }
        }
        elsif ($_->{type} eq 'tree') {
            $_->{href} = url_f('problem_history_tree', %url_params)
        }
    }
    set_history_paths_urls($p->{pid}, $tree->{paths});
    my @items = {
        href => url_f('problem_history_edit',
            file => $p->{file} ? $p->{file} . '/' : '', pid => $p->{pid}, hb => $p->{hb}, new => 1),
        item => res_str(401), new => 1 };
    set_submenu_for_tree_frame($p->{pid}, $p->{hb}, @items);
    $t->param(
        tree => $tree,
        problem_title => $pr->{title},
        title_suffix => $pr->{title},
        problem_import_log => $log,
    );
}

sub detect_encoding_by_xml_header {
    $_[0] =~ /^(?:\xEF\xBB\xBF)?\s*<\?xml.*encoding="(.*)"\s*\?>/ ? uc $1 : 'WINDOWS-1251'
}

sub _is_latest_sha_or_redirect {
    my ($p, $pr) = @_;
    !CATS::Problem::Storage::get_remote_url($pr->{repo}) &&
        $p->{hb} eq CATS::Problem::Storage::get_latest_master_sha($p->{pid})
        or return $p->redirect(url_f 'problem_history', pid => $p->{pid});
}

sub _delete_file {
    my ($p, $pr) = @_;
    _is_latest_sha_or_redirect($p, $pr);
    my $message = 'Delete file ' . $p->{delete_file};

    my CATS::Problem::Storage $ps = CATS::Problem::Storage->new;
    my ($error, $latest_sha, $parsed_problem) = $ps->delete_file(
        $pr->{contest_id}, $p->{pid}, $p->{delete_file}, $message
    );

    unless ($error) {
        $dbh->commit;
        CATS::StaticPages::invalidate_problem_text(pid => $p->{pid});
        return (0, _problem_commitdiff(
            $p, $parsed_problem->{description}->{title},
            $latest_sha, 'UTF-8', $ps->encoded_import_log));
    }

    (1, $ps->encoded_import_log);
}

sub problem_history_blob_frame {
    my ($p) = @_;
    $is_jury or return;
    init_template($p, 'problem_history_blob.html.tt');
    my $pr = _get_problem_info($p) or return $p->redirect(url_f 'contests');

    my $blob = CATS::Problem::Storage::show_blob(
        $p->{pid}, $p->{hb}, $p->{file}, $p->{src_enc} || \&detect_encoding_by_xml_header);
    set_history_paths_urls($p->{pid}, $blob->{paths});
    my @items = $pr->{is_jury} && is_allow_editing($blob, $p->{hb}) ?
        { href => url_f('problem_history_edit',
            file => $p->{file}, hb => $p->{hb}, pid => $p->{pid}), item => res_str(572) } : ();
    set_submenu_for_tree_frame($p->{pid}, $p->{hb}, @items);

    $t->param(
        blob => $blob,
        problem_title => $pr->{title},
        title_suffix => $p->{file},
        source_encodings => source_encodings($blob->{encoding}),
    );
}

sub problem_history_raw_frame {
    my ($p) = @_;
    $is_jury or return;
    _get_problem_info($p) or return $p->redirect(url_f 'contests');

    my $blob = CATS::Problem::Storage::show_raw($p->{pid}, $p->{hb}, $p->{file});
    $p->print_file(
        content_type => $blob->{type},
        file_name => $p->{file},
        content => $blob->{content});
}

sub problem_history_edit_frame {
    my ($p) = @_;
    $is_jury or return;
    my $hash_base = $p->{hb};

    my $pr = _get_problem_info($p)
        or return $p->redirect(url_f 'contests');
    $pr->{is_jury} or return;

    _is_latest_sha_or_redirect($p, $pr);

    init_template($p, 'problem_history_edit.html.tt');

    if ($p->{file} && $p->{file} eq '*') {
        $p->{file} = CATS::Problem::Storage::find_xml($p->{pid}, $hash_base) or return;
    }

    my ($content, $log);
    if (($p->{save} || $p->{upload}) && $p->{src_enc}) {
        ($content, $log) = _save_content($p, $pr);
        defined $log or return;
    }

    my $enc = 'UTF-8';
    if (!defined $p->{new}) {
        my @blob_params = ($p->{pid}, $hash_base, $p->{file});
        my $blob = CATS::Problem::Storage::show_blob(
            @blob_params, $p->{src_enc} || \&detect_encoding_by_xml_header);
        $blob->{content} = $blob->{image} ?
            CATS::Problem::Storage::show_raw(@blob_params)->{content} : $content;
        $enc = ref $blob->{encoding} ? 'UTF-8' : $blob->{encoding};
        set_history_paths_urls($p->{pid}, $blob->{paths});
        $t->param(blob => $blob);
    }
    set_submenu_for_tree_frame($p->{pid}, $hash_base);
    my $keywords = $dbh->selectall_arrayref(q~
        SELECT code FROM keywords~, { Slice => {} });
    my $de_list = CATS::DevEnv->new(CATS::JudgeDB::get_DEs({ fields => 'syntax' }));
    my $de = $de_list->by_file_extension($p->{file});
    $t->param(
        file => $p->{new_name} || $p->{file},
        problem_title => $pr->{title},
        title_suffix => $p->{file},
        src_enc => $enc,
        source_encodings => source_encodings($enc),
        last_commit => CATS::Problem::Storage::get_log($p->{pid}, $hash_base, 1)->[0],
        message => Encode::decode_utf8($p->{message}),
        is_amend => $p->{is_amend},
        problem_import_log => $log,
        cats_tags => $p->{file} && ($p->{file} =~ m/\.xml$/) ?
            [ sort keys %{CATS::Problem::Parser::tag_handlers()} ] : [],
        keywords => $keywords,
        de_list => $de_list,
        de_selected => $de,
        pid => $p->{pid},
        edit_file => !$p->{new},
        hash => $hash_base,
    );
}

sub _save_content {
    my ($p, $pr) = @_;

    !$p->{upload} || $p->{source}
        or return (Encode::decode($p->{enc} // 'UTF-8', $p->{src}), res_str(1205));

    my $hash_base = $p->{hb};
    $p->{src} = $p->{source}->content if $p->{upload};
    my $content = $p->{src};
    undef $p->{new_name} if $p->{file} and $p->{new_name} eq $p->{file};
    undef $p->{file} if $p->{new};

    my CATS::Problem::Storage $ps = CATS::Problem::Storage->new;
    Encode::from_to($content, $p->{enc} // 'UTF-8', $p->{src_enc});
    my ($error, $latest_sha, $parsed_problem) = $ps->change_file(
        $pr->{contest_id}, $p->{pid}, $p->{file} // '', $content,
        $p->{message}, $p->{is_amend} || 0, $p->{new_name}
    );

    unless ($error) {
        $dbh->commit;
        CATS::StaticPages::invalidate_problem_text(pid => $p->{pid});
        return _problem_commitdiff(
            $p, $parsed_problem->{description}->{title},
            $latest_sha, $p->{src_enc}, $ps->encoded_import_log, $p->{new_name});
    }

    $content = Encode::decode($p->{enc} // 'UTF-8', $p->{src});
    return ($content, $ps->encoded_import_log // '');
}

sub problem_history_frame {
    my ($p) = @_;
    $is_jury or return $p->redirect(url_f 'contests');

    my $pr = _get_problem_info($p) or return $p->redirect(url_f 'contests');

    init_template($p, 'problem_history');
    my $lv = CATS::ListView->new(web => $p, name => 'problem_history');

    my $repo = CATS::Problem::Storage::get_repo(
        $p->{pid}, undef, 1, logger => CATS::Problem::Storage->new);

    CATS::Problem::Save::problems_replace($p, $p->{pid}) if $p->{replace};

    my $remote_url = $repo->get_remote_url;
    if ($p->{pull} && $remote_url) {
        $repo->pull($remote_url);
        $t->param(problem_import_log => $repo->{logger}->encoded_import_log);
    }
    $t->param(
        problem_title => $pr->{title},
        pid => $p->{pid},
        remote_url => $remote_url,
        title_suffix => $pr->{title},
        p => $pr,
    );
    CATS::Problem::Utils::problem_submenu('problem_history', $p->{pid});

    my @cols = (
        { caption => res_str(650), width => '25%', order_by => 'author' },
        { caption => res_str(634), width => '10%', order_by => 'author_date' },
        { caption => res_str(651), width => '10%', order_by => 'committer_date' },
        { caption => res_str(652), width => '15%', order_by => 'sha' },
        { caption => res_str(653), width => '40%', order_by => 'message' },
    );
    $lv->define_columns(url_f('problem_history', pid => $p->{pid}), 1, 0, \@cols);
    my $fetch_record = sub {
        my $log = shift @{$_[0]} or return ();
        return (
            %$log,
            href_commit => url_f('problem_history_commit', pid => $p->{pid}, h => $log->{sha}),
            href_tree => url_f('problem_history_tree', pid => $p->{pid}, hb => $log->{sha}),
            href_git_package => url_f('problem_git_package', pid => $p->{pid}, sha => $log->{sha}),
            href_problem_tree => url_f('problem_history_tree', pid => $p->{pid}, hb => $log->{sha}, file => $pr->{repo_path})
        );
    };
    $lv->attach(
        url_f('problem_history', pid => $p->{pid}), $fetch_record,
        $lv->sort_in_memory(CATS::Problem::Storage::get_log($p->{pid})));
}

1;
