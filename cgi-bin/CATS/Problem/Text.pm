package CATS::Problem::Text;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT = qw(
    ensure_problem_hash
    problem_text_frame
);

use Encode;
use Text::Aspell;
use XML::Parser::Expat;

use CATS::Config qw(cats_dir);
use CATS::DB;
use CATS::Misc qw($cid $contest $is_jury $is_root $t $uid auto_ext init_template res_str);
use CATS::Problem::Tags;
use CATS::StaticPages;
use CATS::TeX::Lite;
use CATS::Web qw(param url_param);

my ($current_pid, $html_code, $spellchecker, $text_span, $tags, $skip_depth);

sub check_spelling
{
    my ($word) = @_;
    # The '_' character causes SIGSEGV (!) inside of ASpell.
    return $word if $word =~ /(?:\d|_)/;
    $word =~ s/\x{AD}//g; # Ignore soft hypens.
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
            s/(?<!(?:\w|&))(\w(?:\w|\'|\x{AD})*)/check_spelling($1)/eg;
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
    return if $skip_depth;
    my ($p, $text) = @_;
    # Join consecutive text elements.
    $text_span .= $text;
}


# If the problem was not downloaded yet, generate a hash for it.
sub ensure_problem_hash
{
    my ($problem_id, $hash, $need_commit) = @_;
    return 1 if $$hash;
    my @ch = ('a'..'z', 'A'..'Z', '0'..'9');
    $$hash = join '', map @ch[rand @ch], 1..32;
    $dbh->do(qq~UPDATE problems SET hash = ? WHERE id = ?~, undef, $$hash, $problem_id);
    $dbh->commit if $need_commit;
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
    ensure_problem_hash($current_pid, \$hash, 1);
    return 'unknown' if !$name;
    $ext ||= '';
    # Security: this may lead to duplicate names, e.g. pic1 and pic-1.
    $name =~ tr/a-zA-Z0-9_//cd;
    $ext =~ tr/a-zA-Z0-9_//cd;
    my $fname = "img/img_${hash}_$name.$ext";
    my $fpath = CATS::Misc::downloads_path . $fname;
    -f $fpath or CATS::BinaryFile::save($fpath, $pic);
    return CATS::Misc::downloads_url . $fname;
}


sub save_attachment
{
    my ($name, $need_commit, $pid) = @_;
    $pid ||= $current_pid;
    # Assume the attachment is relatively small (few Kbytes),
    # so it is more efficient to fetch it with the same query as the problem hash.
    my ($data, $file, $hash) = $dbh->selectrow_array(qq~
        SELECT pa.data, pa.file_name, p.hash FROM problem_attachments pa
        INNER JOIN problems p ON pa.problem_id = p.id
        WHERE p.id = ? AND pa.name = ?~, undef,
        $pid, $name);
    ensure_problem_hash($pid, \$hash, $need_commit);
    return 'unknown' if !$file;
    # Security
    $file =~ tr/a-zA-Z0-9_.//cd;
    $file =~ s/\.+/\./g;
    my $fname = "att/${hash}_$file";
    my $fpath = CATS::Misc::downloads_path . $fname;
    -f $fpath or CATS::BinaryFile::save($fpath, $data);
    return CATS::Misc::downloads_url . $fname;
}


sub sh_1
{
    my ($p, $el, %atts) = @_;

    if ($skip_depth) {
        $skip_depth++;
        return;
    }
    if (my $cond = $atts{'cats-if'}) {
        my $pc = CATS::Problem::Tags::parse_tag_condition($cond, sub {});
        if (!CATS::Problem::Tags::check_tag_condition($tags, $pc, sub {})) {
            $skip_depth = 1;
            return;
        }
    }

    if ($el eq 'img' && $atts{picture}) {
        $atts{src} = download_image($atts{picture});
        delete $atts{picture};
    }
    elsif ($el eq 'a' && $atts{attachment}) {
        $atts{href} = save_attachment($atts{attachment}, 1);
        delete $atts{attachment};
    }
    elsif ($el eq 'object' && $atts{attachment}) {
        $atts{data} = save_attachment($atts{attachment}, 1);
        delete $atts{attachment};
    }
    start_element($el, %atts);
}


sub eh_1
{
    my ($p, $el) = @_;
    if ($skip_depth) {
        $skip_depth--;
        return;
    }
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
    $skip_depth and die;
    return $html_code;
}


sub contest_visible
{
    return (1, 1, 1) if $is_root;

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
            C.local_only, C.id AS orig_cid, C.show_packages, C.is_hidden,
            CA.is_jury, CA.is_remote, CA.is_ooc
            FROM contests C $s
            LEFT JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
            WHERE $t.id = ?~, undef,
        $uid, $p);
    return (1, 1, 1) if $c->{is_jury};
    if (($c->{since_start} || 0) > 0 && !$c->{is_hidden}) {
        $c->{local_only} or return (1, $c->{show_packages}, 0);
        defined $uid or return (0, 0, 0);
        # Require local participation.
        return (1, $c->{show_packages}, 0)
            if defined $c->{is_remote} && $c->{is_remote} == 0 || defined $c->{is_ooc} && $c->{is_ooc} == 0;
    }
    return (0, 0, 0);
}


sub problem_text_frame
{
    my ($show, $explain, $is_jury_in_contest) = contest_visible();
    $show or return CATS::Web::not_found;
    $explain = $explain && url_param('explain');

    init_template(auto_ext('problem_text'));

    my (@problems, $show_points);

    if (my $pid = url_param('pid')) {
        push @problems, { problem_id => $pid };
    }
    elsif (my $cpid = url_param('cpid')) {
        my $p = $dbh->selectrow_hashref(qq~
            SELECT CP.id AS cpid, CP.problem_id, CP.code,
            CP.testsets, CP.points_testsets, CP.max_points, CP.tags, CP.status,
            C.rules, L.time_limit, L.memory_limit
            FROM contests C
                INNER JOIN contest_problems CP ON CP.contest_id = C.id
                LEFT JOIN limits L ON L.id = CP.limits_id
            WHERE CP.id = ?~, undef,
            $cpid) or return;
        $show_points = $p->{rules};
        push @problems, $p if $is_jury_in_contest || $p->{status} < $cats::problem_st_hidden;
    }
    else { # Show all problems from the contest.
        ($show_points) = $contest->{rules};
        # Should either check for a static page or hide the problem even from jury.
        my $p = $dbh->selectall_arrayref(qq~
            SELECT CP.id AS cpid, CP.problem_id, CP.code,
            CP.testsets, CP.points_testsets, CP.max_points, CP.tags,
            L.time_limit, L.memory_limit
            FROM contest_problems CP
                LEFT JOIN limits L ON L.id = CP.limits_id
            WHERE contest_id = ? AND status < $cats::problem_st_hidden
            ORDER BY code~, { Slice => {} },
            url_param('cid') || $cid);
        push @problems, @$p;
    }

    my $use_spellchecker = $is_jury_in_contest && !param('nospell');

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

        for (@cats::limits_fields) { delete $p->{$_} if $problem->{$_} }

        $problem = { %$problem, %$p };
        my $lang = $problem->{lang};

        if ($is_jury_in_contest && !param('nokw')) {
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

        $problem->{tags} = param('tags') if $is_jury_in_contest && defined param('tags');
        $tags = CATS::Problem::Tags::parse_tag_condition($problem->{tags}, sub {});
        for my $field_name (qw(statement pconstraints input_format output_format explanation)) {
            for ($problem->{$field_name}) {
                defined $_ or next;
                $text_span = '';
                $_ = $_ eq '' ? undef : parse($_) unless $is_root && param('raw');
                CATS::TeX::Lite::convert_all($_);
                s/(\s|~)(:?-){2,3}(?!-)/($1 ? '&nbsp;' : '') . '&#151;'/ge; # em-dash
            }
        }
        $_ = Encode::decode_utf8($_) for $problem->{json_data};
        $is_jury_in_contest && !param('noformal') or undef $problem->{formal_input};
        $explain or undef $problem->{explanation};
        $problem = {
            %$problem,
            lang_ru => $lang eq 'ru',
            lang_en => $lang eq 'en',
            show_points => $show_points,
        };
    }
    $dbh->commit if $need_commit;

    $t->param(title_suffix => @problems == 1 ? $problems[0]->{title} : res_str(524));
    $t->param(
        problems => \@problems,
        tex_styles => CATS::TeX::Lite::styles(),
        mathjax => !param('nomath'),
        #CATS::TeX::HTMLGen::gen_styles_html()
    );
}


1;
