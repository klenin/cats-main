package CATS::UI::ProblemHistory;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($cid $is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(auto_ext init_template url_f);
use CATS::Problem::Save;
use CATS::Problem::Storage;
use CATS::Problem::Utils;
use CATS::StaticPages;
use CATS::Utils qw(source_encodings);
use CATS::Web qw(content_type encoding_param headers param redirect url_param);

sub problem_commitdiff {
    my ($pid, $title, $sha, $se, $import_log) = @_;

    init_template('problem_history_commit.html.tt');
    my $submenu = [
        { href => url_f('problem_details', pid => $pid), item => res_str(504) },
        { href => url_f('problem_history', pid => $pid), item => res_str(568) },
        { href => url_f('problem_history', a => 'tree', hb => $sha, pid => $pid), item => res_str(570) },
        { href => url_f('problem_git_package', pid => $pid, sha => $sha), item => res_str(569) },
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
    my ($pid, $title) = @_;
    my $sha = url_param('h') or return redirect url_f('problem_history', pid => $pid);
    my $se = param('src_enc') || 'WINDOWS-1251';
    problem_commitdiff($pid, $title, $sha, $se);
}

sub set_history_paths_urls {
    my ($pid, $paths) = @_;
    foreach (@$paths) {
        $_->{href} = url_f('problem_history', a => $_->{type}, file => $_->{name}, pid => $pid, hb => $_->{hash_base});
    }
}

sub set_submenu_for_tree_frame {
    my ($pid, $hash, @items) = @_;
    my $submenu = [
        { href => url_f('problem_details', pid => $pid), item => res_str(504) },
        { href => url_f('problem_history', pid => $pid), item => res_str(568) },
        { href => url_f('problem_history', a => 'commitdiff', pid => $pid, h => $hash), item => res_str(571) },
        { href => url_f('problem_git_package', pid => $pid, sha => $hash), item => res_str(569) },
        @items,
    ];
    $t->param(submenu => $submenu);
}

sub is_allow_editing {
    my ($git_data, $hb) = @_;
    !$git_data->{is_remote} && !$git_data->{image} && $git_data->{latest_sha} eq $hb;
}

sub problem_history_tree_frame {
    my ($pid, $title) = @_;
    my $hash_base = url_param('hb') or return redirect url_f('problem_history', pid => $pid);

    init_template('problem_history_tree.html.tt');

    my $tree = CATS::Problem::Storage::show_tree($pid, $hash_base, url_param('file') || undef, encoding_param('repo_enc'));
    for (@{$tree->{entries}}) {
        $_->{href} = url_f('problem_history', a => $_->{type}, file => $_->{name}, pid => $pid, h => $_->{hash}, hb => $hash_base)
            if $_->{type} eq 'blob' || $_->{type} eq 'tree';
        if ($_->{type} eq 'blob') {
            $_->{href_raw} = url_f('problem_history', a => 'raw', file => $_->{name}, pid => $pid, hb => $hash_base);
            $_->{href_edit} = url_f('problem_history', a => 'edit', file => $_->{name}, pid => $pid, hb => $hash_base)
                if is_allow_editing($tree, $hash_base)
        }
    }
    set_history_paths_urls($pid, $tree->{paths});
    set_submenu_for_tree_frame($pid, $hash_base);
    $t->param(
        tree => $tree,
        problem_title => $title,
        title_suffix => $title,
    );
}

sub detect_encoding_by_xml_header {
    $_[0] =~ /^(?:\xEF\xBB\xBF)?\s*<\?xml.*encoding="(.*)"\s*\?>/ ? uc $1 : 'WINDOWS-1251'
}

sub problem_history_blob_frame {
    my ($pid, $title) = @_;
    my $hash_base = url_param('hb') or return redirect url_f('problem_history', pid => $pid);
    my $file = url_param('file') || undef;

    init_template('problem_history_blob.html.tt');

    my $blob = CATS::Problem::Storage::show_blob(
        $pid, $hash_base, $file, param('src_enc') || \&detect_encoding_by_xml_header);
    set_history_paths_urls($pid, $blob->{paths});
    my @items = is_allow_editing($blob, $hash_base) ?
        { href => url_f('problem_history',
            a => 'edit', file => $file, hb => $hash_base, pid => $pid), item => res_str(572) } : ();
    set_submenu_for_tree_frame($pid, $hash_base, @items);

    $t->param(
        blob => $blob,
        problem_title => $title,
        title_suffix => "$file",
        source_encodings => source_encodings($blob->{encoding}),
    );
}

sub problem_history_raw_frame {
    my ($pid, $title) = @_;
    my $hash_base = url_param('hb') or return redirect url_f('problem_history', pid => $pid);
    my $file = url_param('file') || undef;

    my $blob = CATS::Problem::Storage::show_raw($pid, $hash_base, $file);
    content_type($blob->{type});
    headers('Content-Disposition', "inline; filename=$file");
    CATS::Web::print($blob->{content});
}

sub problem_history_edit_frame {
    $is_root or return;
    my ($pid, $title, $repo_name) = @_;
    my $hash_base = url_param('hb');
    my $file = url_param('file');

    $hash_base && $file &&
        !CATS::Problem::Storage::get_remote_url($repo_name) &&
        $hash_base eq CATS::Problem::Storage::get_latest_master_sha($pid)
        or return redirect url_f('problem_history', pid => $pid);
    init_template('problem_history_edit.html.tt');

    my $se = param('src_enc');
    if (defined param('save') && $se) {
        my $message = param('message');
        my $content = param('source');
        my CATS::Problem::Storage $p = CATS::Problem::Storage->new;
        Encode::from_to($content, encoding_param('enc'), $se);
        my ($error, $latest_sha) = $p->change_file($cid, $pid, $file, $content, $message, param('is_amend') || 0);

        unless ($error) {
            $dbh->commit;
            CATS::StaticPages::invalidate_problem_text(pid => $pid);
            return problem_commitdiff($pid, $title, $latest_sha, $se, $p->encoded_import_log());
        }

        $t->param(
            message => $message,
            content => Encode::decode(encoding_param('enc'), param('source')),
            problem_import_log => $p->encoded_import_log(),
        );
    }

    my $blob = CATS::Problem::Storage::show_blob(
        $pid, $hash_base, $file, $se || \&detect_encoding_by_xml_header);

    set_submenu_for_tree_frame($pid, $hash_base);
    set_history_paths_urls($pid, $blob->{paths});
    $t->param(
        file => $file,
        blob => $blob,
        problem_title => $title,
        title_suffix => "$file",
        src_enc => $blob->{encoding},
        source_encodings => source_encodings($blob->{encoding}),
        last_commit => CATS::Problem::Storage::get_log($pid, $hash_base, 1)->[0],
    );
}

sub problem_history_frame {
    my ($p) = @_;
    $is_jury && $p->{pid} or return redirect url_f('contests');

    my %actions = (
        edit => \&problem_history_edit_frame,
        blob => \&problem_history_blob_frame,
        raw => \&problem_history_raw_frame,
        tree => \&problem_history_tree_frame,
        commitdiff => \&problem_history_commit_frame,
    );

    my ($status, $title, $repo_name) = $dbh->selectrow_array(q~
        SELECT CP.status, P.title, P.repo FROM contest_problems CP
            INNER JOIN problems P ON CP.problem_id = P.id
            WHERE CP.contest_id = ? AND P.id = ?~, undef,
        $cid, $p->{pid});
    defined $status or return redirect url_f('contests');

    if ($p->{a} && exists $actions{$p->{a}}) {
        return $actions{$p->{a}}->($p->{pid}, $title, $repo_name);
    }

    my $lv = CATS::ListView->new(name => 'problem_history', template => auto_ext('problem_history'));

    my $repo = CATS::Problem::Storage::get_repo($p->{pid}, undef, 1, logger => CATS::Problem::Storage->new);

    CATS::Problem::Save::problems_replace if $p->{replace};

    my $remote_url = $repo->get_remote_url;
    if ($p->{pull} && $remote_url) {
        $repo->pull($remote_url);
        $t->param(problem_import_log => $repo->{logger}->encoded_import_log);
    }
    $t->param(
        problem_title => $title,
        pid => $p->{pid},
        remote_url => $remote_url,
        title_suffix => $title,
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
            href_commit => url_f('problem_history', a => 'commitdiff', pid => $p->{pid}, h => $log->{sha}),
            href_tree => url_f('problem_history', a => 'tree', pid => $p->{pid}, hb => $log->{sha}),
            href_git_package => url_f('problem_git_package', pid => $p->{pid}, sha => $log->{sha}),
        );
    };
    $lv->attach(
        url_f('problem_history', pid => $p->{pid}), $fetch_record,
        $lv->sort_in_memory(CATS::Problem::Storage::get_log($p->{pid})));
}

1;
