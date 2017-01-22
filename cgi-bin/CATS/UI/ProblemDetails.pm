package CATS::UI::ProblemDetails;

use strict;
use warnings;

use File::stat;

use CATS::Constants;
use CATS::BinaryFile;
use CATS::DB;
use CATS::Misc qw(
    $t $is_jury $is_root $sid $cid $contest
    init_template res_str url_f auto_ext);
use CATS::ListView qw(init_listview_template order_by sort_listview define_columns attach_listview);
use CATS::Problem::Save;
use CATS::Problem::Text;
use CATS::Utils qw(url_function source_encodings);
use CATS::Web qw(content_type encoding_param headers not_found param redirect url_param);

my $problem_submenu = [
    { href => 'problem_details', item => 504 },
    { href => 'problem_history', item => 568 },
    { href => 'compare_tests', item => 552 },
];

sub problem_submenu
{
    my ($selected_href, $pid) = @_;
    $t->param(
        submenu => [ map +{
            href => url_f($_->{href}, pid => $pid),
            item => res_str($_->{item}),
            selected => $_->{href} eq $selected_href }, @$problem_submenu
        ]
    );
}

sub problem_details_frame {
    my ($p) = @_;
    init_template('problem_details.html.tt');
    $is_jury or return;
    $p->{pid} or return;
    my $pr = $dbh->selectrow_hashref(q~
        SELECT P.title, P.lang, P.contest_id, C.title AS contest_name
        FROM problems P
        INNER JOIN contests C ON C.id = P.contest_id
        WHERE P.id = ?~, { Slice => {} },
        $p->{pid});
    $t->param(
        p => $pr,
        problem_title => $pr->{title},
        title_suffix => $pr->{title},
        href_original_contest => url_function('problems', cid => $pr->{contest_id}, sid => $sid),
        href_git_package => url_f('problem_git_package', pid => $p->{pid}),
    );
    problem_submenu('problem_details', $p->{pid});
}

sub problem_download
{
    my ($p) = @_;
    my $pid = $p->{pid} or return not_found;
    $is_jury || $contest->{show_packages} && $contest->{time_since_start} > 0 && !$contest->{local_only}
        or return not_found;
    # If hash is non-empty, redirect to existing file.
    # Package size is supposed to be large enough to warrant a separate query.
    my ($hash, $status) = $dbh->selectrow_array(q~
        SELECT P.hash, CP.status FROM problems P
        INNER JOIN contest_problems CP ON cp.problem_id = P.id
        WHERE CP.contest_id = ? AND P.id = ?~, undef,
        $cid, $pid);
    defined $status && ($is_jury || $status != $cats::problem_st_hidden)
        or return not_found;
    my $already_hashed = CATS::Problem::Text::ensure_problem_hash($pid, \$hash);
    my $fname = "pr/problem_$hash.zip";
    my $fpath = CATS::Misc::downloads_path . $fname;
    unless($already_hashed && -f $fpath) {
        my ($zip) = $dbh->selectrow_array(qq~
            SELECT zip_archive FROM problems WHERE id = ?~, undef,
            $pid);
        CATS::BinaryFile::save($fpath, $zip);
    }
    redirect(CATS::Misc::downloads_url . $fname);
}

sub problem_git_package
{
    my ($p) = @_;
    my $pid = $p->{pid};
    my $sha = $p->{sha};
    $is_jury && $pid or return redirect url_f('contests');
    my ($status) = $dbh->selectrow_array(qq~
        SELECT status FROM contest_problems
        WHERE contest_id = ? AND problem_id = ?~, undef,
        $cid, $pid) or return;
    undef $t;
    my ($fname, $tree_id) = CATS::ProblemStorage::get_repo_archive($pid, $sha);
    content_type('application/zip');
    headers(
        'Accept-Ranges' => 'bytes',
        'Content-Length' => stat($fname)->size,
        'Content-Disposition' => "attachment; filename=problem_$tree_id.zip",
    );
    CATS::BinaryFile::load($fname, \my $content) or die "open '$fname' failed: $!";
    CATS::Web::print($content);
}

sub problem_commitdiff
{
    my ($pid, $title, $sha, $se, $import_log) = @_;

    init_template('problem_history_commit.html.tt');
    my $submenu = [
        { href => url_f('problem_history', pid => $pid), item => res_str(568) },
        { href => url_f('problem_history', a => 'tree', hb => $sha, pid => $pid), item => res_str(570) },
        { href => url_f('problem_git_package', pid => $pid, sha => $sha), item => res_str(569) },
    ];
    $t->param(
        commit => CATS::ProblemStorage::show_commit($pid, $sha, $se),
        problem_title => $title,
        title_suffix => $title,
        submenu => $submenu,
        problem_import_log => $import_log,
        source_encodings => source_encodings($se),
    );
}

sub problem_history_commit_frame
{
    my ($pid, $title) = @_;
    my $sha = url_param('h') or return redirect url_f('problem_history', pid => $pid);
    my $se = param('src_enc') || 'WINDOWS-1251';
    problem_commitdiff($pid, $title, $sha, $se);
}

sub set_history_paths_urls
{
    my ($pid, $paths) = @_;
    foreach (@$paths) {
        $_->{href} = url_f('problem_history', a => $_->{type}, file => $_->{name}, pid => $pid, hb => $_->{hash_base});
    }
}

sub set_submenu_for_tree_frame
{
    my ($pid, $hash, @items) = @_;
    my $submenu = [
        { href => url_f('problem_history', pid => $pid), item => res_str(568) },
        { href => url_f('problem_history', a => 'commitdiff', pid => $pid, h => $hash), item => res_str(571) },
        { href => url_f('problems_git_package', pid => $pid, sha => $hash), item => res_str(569) },
        @items,
    ];
    $t->param(submenu => $submenu);
}

sub is_allow_editing {
    my ($git_data, $hb) = @_;
    !$git_data->{is_remote} && !$git_data->{image} && $git_data->{latest_sha} eq $hb;
}

sub problem_history_tree_frame
{
    my ($pid, $title) = @_;
    my $hash_base = url_param('hb') or return redirect url_f('problem_history', pid => $pid);

    init_template('problem_history_tree.html.tt');

    my $tree = CATS::ProblemStorage::show_tree($pid, $hash_base, url_param('file') || undef, encoding_param('repo_enc'));
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

sub problem_history_blob_frame
{
    my ($pid, $title) = @_;
    my $hash_base = url_param('hb') or return redirect url_f('problem_history', pid => $pid);
    my $file = url_param('file') || undef;

    init_template('problem_history_blob.html.tt');

    my $se = param('src_enc') || 'WINDOWS-1251';
    my $blob = CATS::ProblemStorage::show_blob($pid, $hash_base, $file, $se);
    set_history_paths_urls($pid, $blob->{paths});
    my @items = is_allow_editing($blob, $hash_base)
              ? { href => url_f('problem_history', a => 'edit', file => $file, hb => $hash_base, pid => $pid), item => res_str(572) }
              : ();
    set_submenu_for_tree_frame($pid, $hash_base, @items);

    $t->param(
        blob => $blob,
        problem_title => $title,
        title_suffix => "$file",
        source_encodings => source_encodings($se),
    );
}

sub problem_history_raw_frame
{
    my ($pid, $title) = @_;
    my $hash_base = url_param('hb') or return redirect url_f('problem_history', pid => $pid);
    my $file = url_param('file') || undef;

    my $blob = CATS::ProblemStorage::show_raw($pid, $hash_base, $file);
    content_type($blob->{type});
    headers('Content-Disposition', "inline; filename=$file");
    CATS::Web::print($blob->{content});
}

sub problem_history_edit_frame
{
    $is_root or return;
    my ($pid, $title, $repo_name) = @_;
    my $hash_base = url_param('hb');
    my $file = url_param('file');

    $hash_base && $file &&
        !CATS::ProblemStorage::get_remote_url($repo_name) &&
        $hash_base eq CATS::ProblemStorage::get_latest_master_sha($pid)
        or return redirect url_f('problem_history', pid => $pid);
    init_template('problem_history_edit_file.html.tt');

    my $se = param('src_enc') || 'WINDOWS-1251';
    if (defined param('save')) {
        my $message = param('message');
        my $content = param('source');
        my CATS::ProblemStorage $p = CATS::ProblemStorage->new;
        Encode::from_to($content, encoding_param('enc'), $se);
        my ($error, $latest_sha) = $p->change_file($cid, $pid, $file, $content, $message, param('is_amend') || 0);

        unless ($error) {
            CATS::StaticPages::invalidate_problem_text(pid => $pid);
            return problem_commitdiff($pid, $title, $latest_sha, $se, $p->encoded_import_log());
        }

        $t->param(
            message => $message,
            content => Encode::decode(encoding_param('enc'), param('source')),
            problem_import_log => $p->encoded_import_log()
        );
    }

    my $blob = CATS::ProblemStorage::show_blob($pid, $hash_base, $file, $se);

    set_submenu_for_tree_frame($pid, $hash_base);
    set_history_paths_urls($pid, $blob->{paths});
    $t->param(
        file => $file,
        blob => $blob,
        problem_title => $title,
        title_suffix => "$file",
        src_enc => $se,
        source_encodings => source_encodings($se),
    );
}

sub problem_history_frame
{
    my $pid = url_param('pid') || 0;
    $is_jury && $pid or return redirect url_f('contests');

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
        $cid, $pid);
    defined $status or return redirect url_f('contests');

    my $action = url_param('a');
    if ($action && exists $actions{$action}) {
        return $actions{$action}->($pid, $title, $repo_name);
    }

    init_listview_template('problem_history', 'problem_history', auto_ext('problem_history'));
    $t->param(problem_title => $title, pid => $pid);

    my $repo = CATS::ProblemStorage::get_repo($pid, undef, 1, logger => CATS::ProblemStorage->new);

    CATS::Problem::Save::problems_replace if defined param('replace');

    my $remote_url = $repo->get_remote_url;
    if (defined param('pull') && $remote_url) {
        $repo->pull($remote_url);
        $t->param(problem_import_log => $repo->{logger}->encoded_import_log);
    }
    $t->param(
        pid => $pid,
        remote_url => $remote_url,
        title_suffix => $title,
    );
    problem_submenu('problem_history', $pid);

    my @cols = (
        { caption => res_str(650), width => '25%', order_by => 'author' },
        { caption => res_str(634), width => '10%', order_by => 'author_date' },
        { caption => res_str(651), width => '10%', order_by => 'committer_date' },
        { caption => res_str(652), width => '15%', order_by => 'sha' },
        { caption => res_str(653), width => '40%', order_by => 'message' }
    );
    define_columns(url_f('problem_history', pid => $pid), 1, 0, \@cols);
    my $fetch_record = sub {
        my $log = shift @{$_[0]} or return ();
        return (
            %$log,
            href_commit => url_f('problem_history', a => 'commitdiff', pid => $pid, h => $log->{sha}),
            href_tree => url_f('problem_history', a => 'tree', pid => $pid, hb => $log->{sha}),
            href_git_package => url_f('problem_git_package', pid => $pid, sha => $log->{sha}),
        );
    };
    attach_listview(url_f('problem_history', pid => $pid), $fetch_record, sort_listview(CATS::ProblemStorage::get_log($pid)));
}

1;
