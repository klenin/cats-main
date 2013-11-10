package CATS::Problem::Text;

use strict;
use warnings;

BEGIN {
    use Exporter;

    our @ISA = qw(Exporter);
    our @EXPORT = qw(
        ensure_problem_hash
        problem_text_frame
    );
}

use CATS::Web qw(param url_param);
use Encode;
use XML::Parser::Expat;
use Text::Aspell;

use CATS::DB;
use CATS::Misc qw($cid $contest $is_jury $t $uid cats_dir auto_ext init_template);
use CATS::StaticPages;

my ($current_pid, $html_code, $spellchecker, $text_span);


sub check_spelling
{
    my ($word) = @_;
    # The '_' character causes SIGSEGV (!) inside of ASpell.
    return $word if $word =~ /(?:\d|_)/;
    # Aspell currently supports only KOI8-R russian encoding.
    my $koi = Encode::encode('KOI8-R', $word);
    return $word if $spellchecker->check($koi);
    my $suggestion =
        Encode::decode('KOI8-R', join ' | ', grep $_, ($spellchecker->suggest($koi))[0..9]);
    return qq~<a class="spell" title="$suggestion">$word</a>~;
}


sub process_text
{
    if ($spellchecker) {
        my @tex_parts = split /\$/, $text_span;
        my $i = 1;
        for (@tex_parts) {
            $i = !$i;
            next if $i;
            # Ignore entities, count apostrophe as part of word except in the beginning of word.
            s/(?<!(?:\w|&))(\w(?:\w|\')*)/check_spelling($1)/eg;
        }
        $html_code .= join '$', @tex_parts;
        # split ignores separator at EOL, m// ignores \n at EOL, hence \z
        $html_code .= '$' if $text_span =~ /\$\z/s;
    }
    else {
        $html_code .= $text_span;
    }
    $text_span = '';
}


sub start_element
{
    my ($el, %atts) = @_;

    process_text;
    $html_code .= "<$el";
    for my $name (keys %atts) {
        my $attrib = $atts{$name};
        $html_code .= qq~ $name="$attrib"~;
    }
    $html_code .= '>';
}


sub end_element
{
    my ($el) = @_;
    process_text;
    $html_code .= "</$el>";
}


sub ch_1
{
    my ($p, $text) = @_;
    # Join consecutive text elements.
    $text_span .= $text;
}


# If the problem was not downloaded yet, generate a hash for it.
sub ensure_problem_hash
{
    my ($problem_id, $hash) = @_;
    return 1 if $$hash;
    my @ch = ('a'..'z', 'A'..'Z', '0'..'9');
    $$hash = join '', map @ch[rand @ch], 1..32;
    $dbh->do(qq~UPDATE problems SET hash = ? WHERE id = ?~, undef, $$hash, $problem_id);
    $dbh->commit;
    return 0;
}


sub download_image
{
    my ($name) = @_;
    # Assume the image is relatively small (few Kbytes),
    # so it is more efficient to fetch it with the same query as the problem hash.
    my ($pic, $ext, $hash) = $dbh->selectrow_array(qq~
        SELECT c.pic, c.extension, p.hash FROM pictures c
        INNER JOIN problems p ON c.problem_id = p.id
        WHERE p.id = ? AND c.name = ?~, undef,
        $current_pid, $name);
    ensure_problem_hash($current_pid, \$hash);
    return 'unknown' if !$name;
    $ext ||= '';
    # Security: this may lead to duplicate names, e.g. pic1 and pic-1.
    $name =~ tr/a-zA-Z0-9_//cd;
    $ext =~ tr/a-zA-Z0-9_//cd;
    my $fname = "./download/img/img_${hash}_$name.$ext";
    -f cats_dir() . $fname or CATS::BinaryFile::save(cats_dir() . $fname, $pic);
    return $fname;
}


sub save_attachment
{
    my ($name) = @_;
    # Assume the attachment is relatively small (few Kbytes),
    # so it is more efficient to fetch it with the same query as the problem hash.
    my ($data, $file, $hash) = $dbh->selectrow_array(qq~
        SELECT pa.data, pa.file_name, p.hash FROM problem_attachments pa
        INNER JOIN problems p ON pa.problem_id = p.id
        WHERE p.id = ? AND pa.name = ?~, undef,
        $current_pid, $name);
    ensure_problem_hash($current_pid, \$hash);
    return 'unknown' if !$file;
    # Security
    $file =~ tr/a-zA-Z0-9_.//cd;
    $file =~ s/\.+/\./g;
    my $fname = "./download/att/${hash}_$file";
    -f cats_dir() . $fname or CATS::BinaryFile::save(cats_dir() . $fname, $data);
    return $fname;
}


sub sh_1
{
    my ($p, $el, %atts) = @_;

    if ($el eq 'img' && $atts{picture}) {
        $atts{src} = download_image($atts{picture});
        delete $atts{picture};
    }
    elsif ($el eq 'a' && $atts{attachment}) {
        $atts{href} = save_attachment($atts{attachment});
        delete $atts{attachment};
    }
    elsif ($el eq 'object' && $atts{attachment}) {
        $atts{data} = save_attachment($atts{attachment});
        delete $atts{attachment};
    }
    start_element($el, %atts);
}


sub eh_1
{
    my ($p, $el) = @_;
    end_element($el);
}


sub parse
{
    my $xml_patch = shift;
    my $parser = XML::Parser::Expat->new;

    $html_code = '';

    $parser->setHandlers(
        'Start' => \&sh_1,
        'End'   => \&eh_1,
        'Char'  => \&ch_1);

    $parser->parse("<div>$xml_patch</div>");
    return $html_code;
}


sub contest_visible
{
    return (1, 1) if $is_jury;

    my $pid = url_param('pid');
    my $cpid = url_param('cpid');
    my $contest_id = url_param('cid') || $cid;

    my ($s, $t, $p) = ('', '', '');
    if (defined $pid) {
        $s = 'INNER JOIN problems P ON C.id = P.contest_id';
        $t = 'P';
        $p = $pid;
    }
    elsif (defined $cpid) {
        $s = 'INNER JOIN contest_problems CP ON C.id = CP.contest_id';
        $t = 'CP';
        $p = $cpid;
    }
    elsif (defined $contest_id) { # Show all problems from the contest.
        $s = '';
        $t = 'C';
        $p = $contest_id;
    }

    my $c = $dbh->selectrow_hashref(qq~
        SELECT
            CAST(CURRENT_TIMESTAMP - C.start_date AS DOUBLE PRECISION) AS since_start,
            C.local_only, C.id AS orig_cid, C.show_packages, C.is_hidden
            FROM contests C $s WHERE $t.id = ?~, undef,
        $p);
    if (($c->{since_start} || 0) > 0 && !$c->{is_hidden}) {
        $c->{local_only} or return (1, $c->{show_packages});
        defined $uid or return (0, 0);
        # Require local participation in the original contest of the problem,
        # or, if all problems from some contest are requested, in that contest.
        # More detailed check leads to complications in non-original contests.
        my ($is_remote) = $dbh->selectrow_array(q~
            SELECT is_remote FROM contest_accounts
            WHERE account_id = ? AND contest_id = ?~, undef,
            $uid, $c->{orig_cid});
        return (1, $c->{show_packages}) if defined $is_remote && $is_remote == 0;
    }
    return (0, 0);
}


sub problem_text_frame
{
    my ($show, $explain) = contest_visible();
    if (!$show) {
        # We cannot return error as html for static pages, since it will cached.
        die 'Request for cached problems of invisible contest'
            if $CATS::StaticPages::is_static_page;
        init_template('access_denied.html.tt');
        return;
    }
    $explain = $explain && url_param('explain');

    init_template(auto_ext('problem_text'));

    my (@problems, $show_points);

    if (my $pid = url_param('pid')) {
        push @problems, { problem_id => $pid };
    }
    elsif (my $cpid = url_param('cpid')) {
        my $p = $dbh->selectrow_hashref(qq~
            SELECT CP.id AS cpid, CP.problem_id, CP.code, CP.testsets, CP.max_points, C.rules
            FROM contests C INNER JOIN contest_problems CP ON CP.contest_id = C.id
            WHERE CP.id = ?~, undef,
            $cpid) or return;
        $show_points = $p->{rules};
        push @problems, $p;
    }
    else { # Show all problems from the contest.
        ($show_points) = $contest->{rules};
        # Should either check for a static page or hide the problem even from jury.
        my $p = $dbh->selectall_arrayref(qq~
            SELECT id AS cpid, problem_id, code, testsets, max_points FROM contest_problems
            WHERE contest_id = ? AND status < $cats::problem_st_hidden
            ORDER BY code~, { Slice => {} },
            url_param('cid') || $cid);
        push @problems, @$p;
    }

    my $use_spellchecker = $is_jury && !param('nospell');

    my $need_commit = 0;
    for my $problem (@problems) {
        $current_pid = $problem->{problem_id};
        my $p = $dbh->selectrow_hashref(qq~
            SELECT
                id, contest_id, title, lang, time_limit, memory_limit,
                difficulty, author, input_file, output_file,
                statement, pconstraints, input_format, output_format, explanation,
                formal_input, json_data, max_points AS max_points_def
            FROM problems WHERE id = ?~, { Slice => {} },
            $problem->{problem_id}) or next;
        $problem = { %$problem, %$p };
        my $lang = $problem->{lang};

        if ($is_jury && !param('nokw')) {
            my $lang_col = $lang eq 'ru' ? 'name_ru' : 'name_en';
            my $kw_list = $dbh->selectcol_arrayref(qq~
                SELECT $lang_col FROM keywords K
                    INNER JOIN problem_keywords PK ON PK.keyword_id = K.id
                    WHERE PK.problem_id = ?
                    ORDER BY 1~, undef,
                $problem->{problem_id});
            $problem->{keywords} = join ', ', @$kw_list;
        }
        if ($use_spellchecker) {
            # Per Text::Aspell docs, we cannot change options of the existing object,
            # so create a new one.
            $spellchecker = Text::Aspell->new;
            $spellchecker->set_option('lang', $lang eq 'ru' ? 'ru_RU' : 'en_US');
        }
        else {
            undef $spellchecker;
        }

        if ($show_points && !$problem->{max_points}) {
            $problem->{max_points} = CATS::RankTable::cache_max_points($problem);
            $need_commit = 1;
        }

        $problem->{samples} = $dbh->selectall_arrayref(qq~
            SELECT rank, in_file, out_file
            FROM samples WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
            $problem->{problem_id});

        for my $field_name qw(statement pconstraints input_format output_format explanation) {
            for ($problem->{$field_name}) {
                defined $_ or next;
                $text_span = '';
                $_ = $_ eq '' ? undef : parse($_);
                CATS::TeX::Lite::convert_all($_);
                s/(\s|~)?-{2,3}/($1 ? '&nbsp;' : '') . '&#151;'/ge; # em-dash
            }
        }
        $_ = Encode::decode_utf8($_) for $problem->{json_data};
        $is_jury && !param('noformal') or undef $problem->{formal_input};
        $explain or undef $problem->{explanation};
        $problem = {
            %$problem,
            lang_ru => $lang eq 'ru',
            lang_en => $lang eq 'en',
            show_points => $show_points,
        };
    }
    $dbh->commit if $need_commit;

    $t->param(title_suffix => $problems[0]->{title}) if @problems == 1;
    $t->param(
        problems => \@problems,
        tex_styles => CATS::TeX::Lite::styles(),
        #CATS::TeX::HTMLGen::gen_styles_html()
    );
}


1;
