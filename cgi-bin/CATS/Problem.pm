package CATS::Problem;

use lib '..';
use strict;
use warnings;

use Encode;
use XML::Parser::Expat;
use JSON::XS;

use CATS::DB;
use CATS::Constants;
use CATS::Misc qw(cats_dir msg);
use CATS::StaticPages;
use CATS::DevEnv;
use CATS::Problem::Parser;
use CATS::Problem::Repository;
use FormalInput;

use fields qw(contest_id id import_log debug source parser encoding old_title replace repo de_list);


sub new
{
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}


sub clear
{
    my CATS::Problem $self = shift;
    undef $self->{$_} for keys %CATS::Problem::FIELDS;
}


sub encoded_import_log
{
    my CATS::Problem $self = shift;
    return $self->{import_log};
}


sub get_repo_id
{
    my ($id, $sha) = @_;
    my ($db_id, $db_sha) = $dbh->selectrow_array(qq~
       SELECT repo, commit_sha FROM problems WHERE id = ?~, undef, $id);
    my $p = cats_dir() . $cats::repos_dir;
    warn 'Repository not found' unless (($db_id ne '' && -d "$p$db_id/") || -d "$p$id/");
    return $db_id =~ '/\d+/' ? ($db_id, $db_sha) : ($id, $sha // '');
}


sub get_repo
{
    my ($pid, $sha, $need_find, %opts) = @_;
    ($pid, $sha) = get_repo_id($pid, $sha) if $need_find;
    $opts{dir} = cats_dir . "$cats::repos_dir$pid/";
    return CATS::Problem::Repository->new(%opts);
}

sub get_repo_archive
{
    my ($pid, $sha) = @_;
    ($pid) = get_repo_id($pid);
    return CATS::Problem::Repository->new(dir => cats_dir . "$cats::repos_dir$pid/")->archive($sha);
}


sub show_commit
{
    my ($pid, $sha, $enc) = @_;
    return get_repo($pid, $sha, 1)->commit_info($sha, $enc);
}


sub get_log
{
    my ($pid, $sha, $max_count) = @_;
    ($pid, $sha) = get_repo_id(@_);
    return get_repo($pid, $sha, 0)->log(sha => $sha, max_count => $max_count);
}


sub add_history
{
    my ($self, $message, $is_amend) = @_;
    $self->{source}->finalize($dbh, $self, $message, $is_amend, get_repo_id($self->{id}));
}


sub load
{
    my CATS::Problem $self = shift;
    ($self->{source}, $self->{contest_id}, $self->{id}, $self->{replace}, $self->{repo}, my $message, my $is_amend) = @_;
    $self->{parser} = CATS::Problem::Parser->new(source => $self->{source}, logger => $self, old_title => $self->{old_title});

    my $error = $self->{parser}->parse;
    if ($error) {
        $self->note("Problem parsing failed");
        return -1;
    }
    eval { $self->persist_problem };
    if ($@) {
        $dbh->rollback unless $self->{debug};
        $self->note("Import failed: $@");
        return -1;
    } else {
        unless ($self->{debug}) {
            $dbh->commit;
            eval { $self->add_history($message, $is_amend); };
            $self->note("Warning: $@") if $@;
        }
        $self->note('Success import');
        return 0;
    }
}


sub delete
{
    my ($cpid) = @_;
    $cpid or die;

    my ($pid, $old_contest, $title, $origin_contest) = $dbh->selectrow_array(q~
        SELECT CP.problem_id, CP.contest_id, P.title, P.contest_id AS orig
        FROM contest_problems CP INNER JOIN problems P ON CP.problem_id = P.id WHERE CP.id = ?~, undef,
        $cpid) or return;

    my ($ref_count) = $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM contest_problems WHERE problem_id = ?~, undef, $pid);
    if ($ref_count > 1) {
        # If at least one contest still references the problem, move all submissions
        # to the "origin" contest. Problem can be removed from the origin only with zero links.
        # To work around this limitation, move the problem to a different contest before deleting.
        $old_contest != $origin_contest or return msg(1136);
        $dbh->do(q~DELETE FROM contest_problems WHERE id = ?~, undef, $cpid);
        $dbh->do(q~
            UPDATE reqs SET contest_id = ? WHERE problem_id = ? AND contest_id = ?~, undef,
            $origin_contest, $pid, $old_contest);
    }
    else {
        # Cascade into contest_problems and reqs.
        $dbh->do(q~DELETE FROM problems WHERE id = ?~, undef, $pid);
        get_repo($pid, undef, 0)->delete;
    }

    CATS::StaticPages::invalidate_problem_text(cid => $old_contest, cpid => $cpid);
    $dbh->commit;
    msg(1022, $title, $ref_count - 1);
}

sub note($)
{
    my CATS::Problem $self = shift;
    $self->{import_log} .= "$_[0]\n";
}


sub warning($)
{
    my CATS::Problem $self = shift;
    $self->{import_log} .= "Warning: $_[0]\n";
}


sub error($)
{
    my CATS::Problem $self = shift;
    $self->{import_log} .= "Error: $_[0]\n";
    die "Unrecoverable error";
}

sub delete_child_records($)
{
    my ($pid) = @_;
    $dbh->do(qq~
        DELETE FROM $_ WHERE problem_id = ?~, undef,
        $pid)
        for qw(
            pictures samples tests testsets problem_sources
            problem_sources_import problem_keywords problem_attachments);
}


sub persist_problem
{
    my CATS::Problem $self = shift;

    return if $self->{debug};

    delete_child_records($self->{id}) if $self->{replace};

    my $sql = $self->{replace}
    ? q~
        UPDATE problems
        SET
            contest_id=?,
            title=?, lang=?, time_limit=?, memory_limit=?, difficulty=?, author=?, input_file=?, output_file=?,
            statement=?, pconstraints=?, input_format=?, output_format=?, formal_input=?, json_data=?, explanation=?, zip_archive=?,
            upload_date=CURRENT_TIMESTAMP, std_checker=?, last_modified_by=?,
            max_points=?, run_method=?, repo=?, hash=NULL
        WHERE id = ?~
    : q~
        INSERT INTO problems (
            contest_id,
            title, lang, time_limit, memory_limit, difficulty, author, input_file, output_file,
            statement, pconstraints, input_format, output_format, formal_input, json_data, explanation, zip_archive,
            upload_date, std_checker, last_modified_by,
            max_points, run_method, repo, id
        ) VALUES (
            ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP,?,?,?,?,?,?
        )~;

    my $c = $dbh->prepare($sql);
    my $i = 1;
    $c->bind_param($i++, $self->{contest_id});
    $c->bind_param($i++, $self->{parser}->{problem}->{$_})
        for qw(title lang time_limit memory_limit difficulty author input_file output_file);
    $c->bind_param($i++, $self->{parser}->{$_}, { ora_type => 113 })
        for qw(statement constraints input_format output_format formal_input json_data explanation);
    $c->bind_param($i++, $self->{parser}->get_zip);
    $c->bind_param($i++, $self->{parser}->{problem}->{std_checker});
    $c->bind_param($i++, $CATS::Misc::uid);
    $c->bind_param($i++, $self->{parser}->{problem}->{max_points});
    $c->bind_param($i++, $self->{parser}->{run_method});
    $c->bind_param($i++, $self->{repo});
    $c->bind_param($i++, $self->{id});
    $c->execute;

    $self->insert_problem_content;
}


sub get_de_id
{
    my CATS::Problem $self = shift;
    my ($code, $path) = @_;

    $self->{de_list} ||= CATS::DevEnv->new($dbh);

    my $de;
    if (defined $code) {
        $de = $self->{de_list}->by_code($code)
            or $self->error("Unknown DE code: '$code' for source: '$path'");
    }
    else {
        $de = $self->{de_list}->by_file_extension($path)
            or $self->error("Can't detect de for source: '$path'");
        $self->note("Detected DE: '$de->{description}' for source: '$path'");
    }
    return $de->{id};
}


sub insert_problem_source
{
    my CATS::Problem $self = shift;
    my %p = @_;
    use Carp;
    my $s = $p{source_object} or confess;

    if ($s->{guid}) {
        my $dup_id = $dbh->selectrow_array(qq~
            SELECT problem_id FROM problem_sources WHERE guid = ?~, undef, $s->{guid});
        $self->warning("Duplicate guid with problem $dup_id") if $dup_id;
    }
    my $c = $dbh->prepare(qq~
        INSERT INTO problem_sources (
            id, problem_id, de_id, src, fname, stype, input_file, output_file, guid,
            time_limit, memory_limit
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?)~);

    $c->bind_param(1, $s->{id});
    $c->bind_param(2, $self->{id});
    $c->bind_param(3, $self->get_de_id($s->{de_code}, $s->{path}));
    $c->bind_param(4, $s->{src}, { ora_type => 113 });
    $c->bind_param(5, $s->{path});
    $c->bind_param(6, $p{source_type});
    $c->bind_param(7, $s->{inputFile});
    $c->bind_param(8, $s->{outputFile});
    $c->bind_param(9, $s->{guid});
    $c->bind_param(10, $s->{time_limit});
    $c->bind_param(11, $s->{memory_limit});
    $c->execute;

    my $g = $s->{guid} ? ", guid=$s->{guid}" : '';
    $self->note("$p{type_name} '$s->{path}' added$g");
}


sub insert_problem_content
{
    my CATS::Problem $self = shift;

    my $p = $self->{parser}->{problem};

    $self->{parser}->{has_checker} or $self->error('No checker specified');

    if ($p->{std_checker}) {
        $self->note("Checker: $p->{std_checker}");
    } elsif (my $c = $self->{parser}->{checker}) {
        $self->insert_problem_source(
            source_object => $c, type_name => 'Checker',
            source_type => CATS::Problem::Parser::checker_type_names->{$c->{style}},
        );
    }

    for (@{$self->{parser}->{validators}}) {
        $self->insert_problem_source(
            source_object => $_, type_name => 'Validator', source_type => $cats::validator
        )
    }

    for(@{$self->{parser}->{generators}}) {
        $self->insert_problem_source(
            source_object => $_, source_type => $cats::generator, type_name => 'Generator');
    }

    for(@{$self->{parser}->{solutions}}) {
        $self->insert_problem_source(
            source_object => $_, type_name => 'Solution',
            source_type => $_->{checkup} ? $cats::adv_solution : $cats::solution);
    }

    for (@{$self->{parser}->{modules}}) {
        $self->insert_problem_source(
            source_object => $_, source_type => $_->{type_code},
            type_name => "Module for $_->{type}");
    }

    for (@{$self->{parser}->{imports}}) {
        $dbh->do(q~
            INSERT INTO problem_sources_import (problem_id, guid) VALUES (?, ?)~, undef,
            $self->{id}, $_->{guid});
    }

    for my $ts (values %{$self->{parser}->{testsets}}) {
        $dbh->do(q~
            INSERT INTO testsets (id, problem_id, name, tests, points, comment, hide_details)
            VALUES (?, ?, ?, ?, ?, ?, ?)~, undef,
            $ts->{id}, $self->{id}, @{$ts}{qw(name tests points comment hideDetails)});
    }

    my $c = $dbh->prepare(qq~
        INSERT INTO pictures(id, problem_id, extension, name, pic)
            VALUES (?,?,?,?,?)~);
    for (@{$self->{parser}->{pictures}}) {

        $c->bind_param(1, $_->{id});
        $c->bind_param(2, $self->{id});
        $c->bind_param(3, $_->{ext});
        $c->bind_param(4, $_->{name} );
        $c->bind_param(5, $_->{src}, { ora_type => 113 });
        $c->execute;

        $self->note("Picture '$_->{path}' added");
        $_->{refcount}
            or $self->warning("No references to picture '$_->{path}'");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO problem_attachments(id, problem_id, name, file_name, data)
            VALUES (?,?,?,?,?)~);
    for (@{$self->{parser}->{attachments}}) {

        $c->bind_param(1, $_->{id});
        $c->bind_param(2, $self->{id});
        $c->bind_param(3, $_->{name});
        $c->bind_param(4, $_->{file_name});
        $c->bind_param(5, $_->{src}, { ora_type => 113 });
        $c->execute;

        $self->note("Attachment '$_->{path}' added");
        $_->{refcount}
            or $self->warning("No references to attachment '$_->{path}'");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO tests (
            problem_id, rank, input_validator_id, generator_id, param, std_solution_id, in_file, out_file,
            points, gen_group
        ) VALUES (?,?,?,?,?,?,?,?,?,?)~
    );

    for (sort { $a->{rank} <=> $b->{rank} } values %{$self->{parser}->{tests}}) {
        $c->bind_param(1, $self->{id});
        $c->bind_param(2, $_->{rank});
        $c->bind_param(3, $_->{input_validator_id});
        $c->bind_param(4, $_->{generator_id});
        $c->bind_param(5, $_->{param});
        $c->bind_param(6, $_->{std_solution_id} );
        $c->bind_param(7, $_->{in_file}, { ora_type => 113 });
        $c->bind_param(8, $_->{out_file}, { ora_type => 113 });
        $c->bind_param(9, $_->{points});
        $c->bind_param(10, $_->{gen_group});
        $c->execute
            or $self->error("Can not add test $_->{rank}: $dbh->errstr");
        $self->note("Test $_->{rank} added");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO samples (problem_id, rank, in_file, out_file)
        VALUES (?,?,?,?)~
    );
    for (values %{$self->{parser}->{samples}}) {
        $c->bind_param(1, $self->{id});
        $c->bind_param(2, $_->{rank});
        $c->bind_param(3, $_->{in_file}, { ora_type => 113 });
        $c->bind_param(4, $_->{out_file}, { ora_type => 113 });
        $c->execute;
        $self->note("Sample test $_->{rank} added");
    }

    $c = $dbh->prepare(qq~
        INSERT INTO problem_keywords (problem_id, keyword_id) VALUES (?, ?)~);
    for (keys %{$self->{parser}->{keywords}}) {
        my ($keyword_id) = $dbh->selectrow_array(q~
            SELECT id FROM keywords WHERE code = ?~, undef, $_);
        if ($keyword_id) {
            $c->execute($self->{id}, $keyword_id);
            $self->note("Keyword added: $_");
        }
        else {
            $self->warning("Unknown keyword: $_");
        }
    }
}


1;
