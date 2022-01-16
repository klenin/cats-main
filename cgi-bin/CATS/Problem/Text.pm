package CATS::Problem::Text;

use strict;
use warnings;

use Encode;
use XML::Parser::Expat;

use CATS::Constants;
use CATS::Config qw(cats_dir);
use CATS::DB qw(:DEFAULT $db);
use CATS::Globals qw($cid $contest $is_jury $is_root $t $uid);
use CATS::Messages qw(res_str);
use CATS::Output qw(downloads_path downloads_url init_template url_f);
use CATS::Problem::Spell;
use CATS::Problem::Submit qw(prepare_de_list);
use CATS::Problem::Tags;
use CATS::Problem::Utils;
use CATS::Score;
use CATS::StaticPages;
use CATS::TeX::Lite;
use CATS::Time;
use CATS::Utils qw(url_function);

my (
    $current_pid, $html_code, $spellchecker, $text_span, $tags, $skip_depth, $verbatim_depth,
    $has_snippets, $noif, $has_quizzes, $has_static_highlight);
my $wrapper = 'cats-wrapper';
my @parsed_fields = qw(statement pconstraints input_format output_format explanation);

my $verbatim_tags = { code => 1, script => 1, svg => 1, style => 1 };
my $empty_tags = { br => 1, hr => 1, img => 1 };

sub _xml_quote_topicalizer {
    s/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g;
}

sub process_text {
    if ($verbatim_depth) {
        #_xml_quote_topicalizer for $text_span;
        $html_code .= $text_span;
        $text_span = '';
        return;
    }
    while ($text_span =~ /([^\$]*)(?:(\$+)([^\$]+)(\$*))?/g) {
        my ($text, $tex_sep1, $tex, $tex_sep2) = ($1, $2, $3, $4);
        if ($text ne '') {
            for ($text) {
                #_xml_quote_topicalizer;
                s/(\s|~)(:?-){2,3}(?!-)/($1 ? '&nbsp;' : '') . '&#8212;'/ge; # Em-dash.
                s/``/\xAB/g; # Left guillemet.
                s/''/\xBB/g; # Right guillemet.
                $spellchecker->check_topicalizer if $spellchecker;
            }
            $html_code .= $text;
        }
        if ($tex_sep1) {
            $html_code .= '<b>Unbalanced TeX</b>' if $tex_sep1 ne $tex_sep2;
            $html_code .= CATS::TeX::Lite::convert_one($tex);
        }
    }
    $text_span = '';
}

sub _on_char {
    return if $skip_depth;
    my ($p, $text) = @_;
    # Join consecutive text elements.
    $text_span .= $text;
}

sub download_image {
    my ($name) = @_;
    # Assume the image is relatively small (few Kbytes),
    # so it is more efficient to fetch it with the same query as the problem hash.
    my ($pic, $ext, $hash) = $dbh->selectrow_array(qq~
        SELECT c.pic, c.extension, p.hash FROM pictures c
        INNER JOIN problems p ON c.problem_id = p.id
        WHERE p.id = ? AND c.name = ?~, undef,
        $current_pid, $name);
    CATS::Problem::Utils::ensure_problem_hash($current_pid, \$hash, 1);
    return 'unknown' if !$name;
    $ext ||= '';
    # Security: this may lead to duplicate names, e.g. pic1 and pic-1.
    $name =~ tr/a-zA-Z0-9_//cd;
    $ext =~ tr/a-zA-Z0-9_//cd;
    my $fname = "img/img_${hash}_$name.$ext";
    my $fpath = downloads_path . $fname;
    -f $fpath or CATS::BinaryFile::save($fpath, $pic);
    return downloads_url . $fname;
}

sub save_attachment {
    my ($name, $need_commit, $pid) = @_;
    $pid ||= $current_pid;
    # Assume the attachment is relatively small (few Kbytes),
    # so it is more efficient to fetch it with the same query as the problem hash.
    my ($data, $file, $hash) = $dbh->selectrow_array(qq~
        SELECT pa.data, pa.file_name, p.hash FROM problem_attachments pa
        INNER JOIN problems p ON pa.problem_id = p.id
        WHERE p.id = ? AND pa.name = ?~, undef,
        $pid, $name);
    CATS::Problem::Utils::ensure_problem_hash($pid, \$hash, $need_commit);
    return 'unknown' if !$file;
    # Security
    $file =~ tr/a-zA-Z0-9_.//cd;
    $file =~ s/\.+/\./g;
    my $fname = "att/${hash}_$file";
    my $fpath = downloads_path . $fname;
    -f $fpath or CATS::BinaryFile::save($fpath, $data);
    return downloads_url . $fname;
}

sub _on_start {
    my ($p, $el, %atts) = @_;
    return if $el eq $wrapper;

    if ($skip_depth) {
        $skip_depth++;
        return;
    }
    if (my $cond = $atts{'cats-if'}) {
        my $pc = CATS::Problem::Tags::parse_tag_condition($cond, sub {});
        my $cond_true = CATS::Problem::Tags::check_tag_condition($tags, $pc, sub {});
        if ($noif) {
            $atts{class} .= $cond_true ? ' cond_true' : ' cond_false';
            $atts{title} .= $cond;
        }
        elsif (!$cond_true) {
            $skip_depth = 1;
            return;
        }
    }
    $has_snippets = 1 if $atts{'cats-snippet'};

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
    elsif ($el eq 'Quiz') {
        $has_quizzes = 1;
    }
    elsif ($el eq 'code' && $atts{language}) {
        $has_static_highlight = 1;
    }

    process_text;
    ++$verbatim_depth if $verbatim_tags->{lc($el)};
    if ($spellchecker) {
        my $lang = $atts{lang};
        # Do not spellcheck code unless explicitly requested.
        $lang //= 'code' if $verbatim_tags->{lc($el)};
        $spellchecker->push_lang($lang, $atts{'cats-dict'});
    }
    $html_code .= "<$el";
    for my $name (keys %atts) {
        for ($atts{$name}) {
            _xml_quote_topicalizer;
            $html_code .= qq~ $name="$_"~;
        }
    }
    $html_code .= '>';
}

sub _on_end {
    my ($p, $el) = @_;
    if ($skip_depth) {
        $skip_depth--;
        return;
    }
    process_text;
    --$verbatim_depth if $verbatim_tags->{lc($el)};
    return if $el eq $wrapper;
    $spellchecker->pop_lang if $spellchecker;
    # <br></br> is interpreted by browser as two <br>s, enforce <br/> form.
    if ($empty_tags->{$el} && $html_code =~ />$/) {
        substr($html_code, length($html_code) - 1, 1) = '/>';
    }
    else {
        $html_code .= "</$el>";
    }
}

sub _parse {
    my ($xml_patch) = @_;
    my $parser = XML::Parser::Expat->new;

    $html_code = '';

    $parser->setHandlers(Start => \&_on_start, End => \&_on_end, Char => \&_on_char);

    # XML parser requires all text to be inside of top-level tag.
    eval { $parser->parse("<$wrapper>$xml_patch</$wrapper>"); 1; } or return $@;
    $skip_depth and die;
    $verbatim_depth and die;
    $html_code;
}

sub get_tags {
    my ($pid) = @_;
    $pid && $is_root or return [];

    my $parser = XML::Parser::Expat->new;

    my $problem = $dbh->selectrow_hashref(
        _u $sql->select('problems', \@parsed_fields, { id => $pid })) or return;

    my %tags;
    $parser->setHandlers(Start => sub {
        my ($p, $el, %attrs) = @_;
        my $cond = $attrs{'cats-if'} or return;
        my $pc = CATS::Problem::Tags::parse_tag_condition($cond, sub {});
        $tags{$_} = 1 for keys %$pc;
    });

    my $all_text = join '', grep $_, map $problem->{$_}, @parsed_fields;
    eval { $parser->parse("<$wrapper>$all_text</$wrapper>"); };

    [ sort keys %tags ];
}

sub _all_visible { { author => 1, explain => $_[0]->{explain}, is_jury_in_contest => 1 } };

sub _contest_visible {
    my ($p) = @_;
    return _all_visible($p) if $is_root;

    my $pid = $p->{pid};
    my $cpid = $p->{cpid};
    my $contest_id = $p->{cid} || $cid;

    my ($s, $t, $q) = ('', '', '');
    if (defined $pid) {
        $s = 'INNER JOIN problems P ON C.id = P.contest_id';
        $t = 'P';
        $q = $pid;
    }
    elsif (defined $cpid) {
        $s = 'INNER JOIN contest_problems CP ON C.id = CP.contest_id';
        $t = 'CP';
        $q = $cpid;
    }
    elsif (defined $contest_id) { # Show all problems from the contest.
        $s = '';
        $t = 'C';
        $q = $contest_id;
    }

    my $c = $dbh->selectrow_hashref(qq~
        SELECT
            CAST(CURRENT_TIMESTAMP - $CATS::Time::contest_start_offset_sql AS DOUBLE PRECISION) AS since_start,
            CAST(CURRENT_TIMESTAMP - $CATS::Time::contest_finish_offset_sql AS DOUBLE PRECISION) AS since_finish,
            C.local_only, C.id AS orig_cid, C.show_explanations, C.is_hidden, C.is_official,
            CA.id AS caid, CA.is_jury, CA.is_remote, CA.is_ooc
            FROM contests C $s
            LEFT JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
            LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
            WHERE $t.id = ?~, undef,
        $uid, $q);
    return _all_visible($p) if $c->{is_jury};
    ($c->{since_start} || 0) > 0 && (!$c->{is_hidden} || $c->{caid}) or return;
    my $res = {
        explain => $c->{show_explanations} && $p->{explain},
        author => !$c->{is_official} || $c->{since_finish} > 0,
    };
    $c->{local_only} or return $res;
    # Require local participation.
    defined $uid &&
    (defined $c->{is_remote} && $c->{is_remote} == 0 || defined $c->{is_ooc} && $c->{is_ooc} == 0)
        or return;
    $res;
}

sub choose_lang {
    my ($problem, $p, $is_jury_in_contest) = @_;

    my @langs = split ',', $problem->{lang};
    my $lang_tag = $problem->{parsed_tags}->{lang}->[1];
    $problem->{langs} = $lang_tag ? [] : \@langs;
    if ($p->{pl}) {
        return $p->{pl} if
            $is_jury_in_contest && !$CATS::StaticPages::is_static_page ||
            !$lang_tag && grep $_ eq $p->{pl}, @langs;
    }
    $lang_tag || $langs[0];
}

sub _ignore_errors {}

sub problem_text {
    my ($p) = @_;
    my $v = _contest_visible($p) or return $p->not_found;

    init_template($p, 'problem_text');

    my (@problems, $show_points);

    my $overridden_limits_str = join ', ', map "L.$_", @cats::limits_fields;

    if ($p->{cpid} || $p->{pid}) {
        my ($cond, @params) = $p->{cpid} ?
            ('CP.id = ?', $p->{cpid}) :
            ('CP.problem_id = ? AND CP.contest_id = (SELECT P.contest_id FROM problems P WHERE P.id = ?)',
                $p->{pid}, $p->{pid});
        my $pr = $dbh->selectrow_hashref(qq~
            SELECT
                CP.id AS cpid, CP.contest_id, CP.problem_id, CP.code, CP.color,
                CP.testsets, CP.points_testsets, CP.max_points, CP.tags, CP.status,
                C.rules, $overridden_limits_str
            FROM contests C
                INNER JOIN contest_problems CP ON CP.contest_id = C.id
                LEFT JOIN limits L ON L.id = CP.limits_id
            WHERE $cond~, undef,
            @params) or return;
        $show_points = $pr->{rules};
        push @problems, $pr if $v->{is_jury_in_contest} || $pr->{status} < $cats::problem_st_hidden;
    }
    else { # Show all problems from the contest.
        ($show_points) = $contest->{rules};
        # Should either check for a static page or hide the problem even from jury.
        my $prs = $dbh->selectall_arrayref(qq~
            SELECT
                CP.id AS cpid, CP.contest_id, CP.problem_id, CP.code,
                CP.testsets, CP.points_testsets, CP.max_points, CP.tags, CP.status,
                $overridden_limits_str
            FROM contest_problems CP
                LEFT JOIN limits L ON L.id = CP.limits_id
            WHERE (CP.contest_id = ? OR
                EXISTS (SELECT 1 FROM contests C1 WHERE C1.parent_id = ? AND CP.contest_id = C1.id))
            AND CP.status < $cats::problem_st_hidden
            ORDER BY CP.contest_id, CP.code~, { Slice => {} },
            $p->{cid} || $cid, $p->{cid} || $cid);
        push @problems, @$prs;
    }

    my $site_tags = @problems && $uid && $dbh->selectrow_array(q~
        SELECT CS.problem_tag FROM contest_accounts CA
        INNER JOIN contest_sites CS ON CS.site_id = CA.site_id AND CS.contest_id = CA.contest_id
        WHERE CA.contest_id = ? AND account_id = ?~, undef,
        $problems[0]->{contest_id}, $uid);

    $spellchecker = $v->{is_jury_in_contest} && !$p->{nospell} ? CATS::Problem::Spell->new : undef;
    $noif = $v->{is_jury_in_contest} && $p->{noif};

    my $static_path = $CATS::StaticPages::is_static_page ? '../' : '';

    $has_snippets = $has_quizzes = $has_static_highlight = 0;
    my $need_commit = 0;
    for my $problem (@problems) {
        $current_pid = $problem->{problem_id};
        {
            my $fields_str = join ', ', (qw(
                id title lang difficulty input_file output_file statement pconstraints json_data run_method),
                'contest_id AS orig_contest_id',
                'max_points AS max_points_def',
                ($v->{author} && !$p->{noauthor} ? ('author') : ()),
                grep(!$problem->{$_}, @cats::limits_fields),
                ($v->{explain} ? 'explanation' : ()),
                ($p->{noformats} ? () : qw(input_format output_format)),
                ($v->{is_jury_in_contest} && !$p->{noformal} ? 'formal_input' : ()),
            );
            my $p_orig = $dbh->selectrow_hashref(qq~
                SELECT $fields_str FROM problems WHERE id = ?~, { Slice => {} },
                $problem->{problem_id}) or next;
            $problem = { %$problem, %$p_orig };
        }
        $problem->{tags} = $p->{tags} if $v->{is_jury_in_contest} && defined $p->{tags};
        $problem->{parsed_tags} = $tags = CATS::Problem::Tags::parse_tag_condition(
            $problem->{tags}, _ignore_errors);
        if ($site_tags) {
            my $t = CATS::Problem::Tags::parse_tag_condition($site_tags, _ignore_errors);
            $tags->{$_} = $t->{$_} for keys %$t;
        }
        $problem->{lang} = choose_lang($problem, $p, $v->{is_jury_in_contest});
        $problem->{iface_lang} = (grep $_ eq $problem->{lang}, @cats::langs) ? $problem->{lang} : 'en';
        $tags->{lang} = [ 0, $problem->{lang} ];
        $problem->{interactive_io} = $problem->{run_method} != $cats::rm_default;
        CATS::Problem::Utils::round_time_limit($problem->{time_limit});

        if ($v->{is_jury_in_contest} && !$p->{nokw}) {
            my $lang_col = $problem->{lang} eq 'ru' ? 'name_ru' : 'name_en';
            my $kw_list = $dbh->selectcol_arrayref(qq~
                SELECT $lang_col FROM keywords K
                    INNER JOIN problem_keywords PK ON PK.keyword_id = K.id
                WHERE PK.problem_id = ?
                ORDER BY 1~, undef,
                $problem->{problem_id});
            $problem->{keywords} = join ', ', @$kw_list;
        }

        $problem->{show_points} = $show_points;
        if ($problem->{status} == $cats::problem_st_nosubmit) {
            $problem->{max_points} = undef;
        }
        elsif ($show_points && !$problem->{max_points}) {
            $problem->{max_points} = CATS::Score::cache_max_points($problem);
            $need_commit = 1;
        }

        $problem->{samples} = $dbh->selectall_arrayref(qq~
            SELECT rank,
                CAST(in_file AS $db->{TEXT_TYPE}) AS in_file,
                CAST(out_file AS $db->{TEXT_TYPE}) AS out_file
            FROM samples WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
            $problem->{problem_id});

        $problem->{href_problem_list} = $static_path .
            url_function('problems', cid => $problem->{contest_id} || $problem->{orig_contest_id});
        $problem->{href_get_snippets} = $static_path .
            url_function('get_snippets', cpid => $problem->{cpid});

        $spellchecker->push_lang($problem->{lang}) if $spellchecker;
        for my $field_name (@parsed_fields) {
            for ($problem->{$field_name}) {
                defined $_ or next;
                $text_span = '';
                $_ = $_ eq '' ? undef : _parse($_) unless $is_root && $p->{raw};
            }
        }
        $spellchecker->pop_lang if $spellchecker;
        $_ = Encode::decode_utf8($_) for $problem->{json_data};
    }
    $dbh->commit if $need_commit;

    my %de = prepare_de_list;
    ($de{quiz_de}) =
        grep $_->{code} && $_->{code} == $CATS::Globals::quiz_de_code, @{$de{de_list}};
    $t->param(
        title_suffix => (@problems == 1 ? $problems[0]->{title} : res_str(524)),
        problems => \@problems,
        tex_styles => CATS::TeX::Lite::styles(),
        mathjax => !$p->{nomath},
        has_snippets => $has_snippets,
        has_quizzes => $has_quizzes,
        has_static_highlight => $has_static_highlight,
        %de,
        href_static_path => $static_path,
        href_submit_problem => $static_path . url_function('api_submit_problem'),
        href_get_sources_info => $static_path . url_function('api_get_sources_info'),
        href_get_last_verdicts => @problems > 100 ? undef : $static_path .
            url_function('api_get_last_verdicts', problem_ids => join ',', map $_->{cpid}, @problems),
    );
}

1;
