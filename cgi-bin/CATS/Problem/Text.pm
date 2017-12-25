package CATS::Problem::Text;

use strict;
use warnings;

use Encode;
use XML::Parser::Expat;

use CATS::Constants;
use CATS::Config qw(cats_dir);
use CATS::DB;
use CATS::Globals qw($cid $contest $is_jury $is_root $t $uid);
use CATS::Messages qw(res_str);
use CATS::Output qw(auto_ext downloads_path downloads_url init_template);
use CATS::Problem::Spell;
use CATS::Problem::Tags;
use CATS::Problem::Utils;
use CATS::StaticPages;
use CATS::TeX::Lite;
use CATS::Time;
use CATS::Utils qw(url_function);

my ($current_pid, $html_code, $spellchecker, $text_span, $tags, $skip_depth);

sub process_text {
    if ($spellchecker) {
        my @tex_parts = split /\$/, $text_span;
        my $i = 0;
        for (@tex_parts) {
            $spellchecker->check_topicalizer if $i ^= 1;
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

sub start_element {
    my ($el, %atts) = @_;

    process_text;
    if ($spellchecker) {
        my $lang = $atts{lang};
        # Do not spellcheck code unless explicitly requested.
        $lang //= 'code' if lc($el) eq 'code';
        $spellchecker->push_lang($lang, $atts{'cats-dict'});
    }
    $html_code .= "<$el";
    for my $name (keys %atts) {
        my $attrib = $atts{$name};
        $html_code .= qq~ $name="$attrib"~;
    }
    $html_code .= '>';
}

sub end_element {
    my ($el) = @_;
    process_text;
    $spellchecker->pop_lang if $spellchecker;
    $html_code .= "</$el>";
}

sub ch_1 {
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

sub sh_1 {
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

sub eh_1 {
    my ($p, $el) = @_;
    if ($skip_depth) {
        $skip_depth--;
        return;
    }
    end_element($el);
}

sub parse {
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

sub contest_visible {
    my ($p) = @_;
    return (1, 1, 1) if $is_root;

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
            C.local_only, C.id AS orig_cid, C.show_packages, C.is_hidden,
            CA.id AS caid, CA.is_jury, CA.is_remote, CA.is_ooc
            FROM contests C $s
            LEFT JOIN contest_accounts CA ON CA.contest_id = C.id AND CA.account_id = ?
            LEFT JOIN contest_sites CS ON CS.contest_id = C.id AND CS.site_id = CA.site_id
            WHERE $t.id = ?~, undef,
        $uid, $q);
    return (1, 1, 1) if $c->{is_jury};
    if (($c->{since_start} || 0) > 0 && (!$c->{is_hidden} || $c->{caid})) {
        $c->{local_only} or return (1, $c->{show_packages}, 0);
        defined $uid or return (0, 0, 0);
        # Require local participation.
        return (1, $c->{show_packages}, 0)
            if defined $c->{is_remote} && $c->{is_remote} == 0 || defined $c->{is_ooc} && $c->{is_ooc} == 0;
    }
    return (0, 0, 0);
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

sub problem_text {
    my ($p) = @_;
    my ($show, $explain, $is_jury_in_contest) = contest_visible($p);
    $show or return CATS::Web::not_found;
    $explain = $explain && $p->{explain};

    init_template(auto_ext('problem_text'));

    my (@problems, $show_points);

    my $overridden_limits_str = join ', ', map "L.$_", @cats::limits_fields;

    if (my $pid = $p->{pid}) {
        push @problems, { problem_id => $pid };
    }
    elsif (my $cpid = $p->{cpid}) {
        my $pr = $dbh->selectrow_hashref(qq~
            SELECT
                CP.id AS cpid, CP.contest_id, CP.problem_id, CP.code,
                CP.testsets, CP.points_testsets, CP.max_points, CP.tags, CP.status,
                C.rules, $overridden_limits_str
            FROM contests C
                INNER JOIN contest_problems CP ON CP.contest_id = C.id
                LEFT JOIN limits L ON L.id = CP.limits_id
            WHERE CP.id = ?~, undef,
            $cpid) or return;
        $show_points = $pr->{rules};
        push @problems, $pr if $is_jury_in_contest || $pr->{status} < $cats::problem_st_hidden;
    }
    else { # Show all problems from the contest.
        ($show_points) = $contest->{rules};
        # Should either check for a static page or hide the problem even from jury.
        my $prs = $dbh->selectall_arrayref(qq~
            SELECT
                CP.id AS cpid, CP.contest_id, CP.problem_id, CP.code,
                CP.testsets, CP.points_testsets, CP.max_points, CP.tags,
                $overridden_limits_str
            FROM contest_problems CP
                LEFT JOIN limits L ON L.id = CP.limits_id
            WHERE CP.contest_id = ? AND CP.status < $cats::problem_st_hidden
            ORDER BY CP.code~, { Slice => {} },
            $p->{cid} || $cid);
        push @problems, @$prs;
    }

    $spellchecker = $is_jury_in_contest && !$p->{nospell} ? CATS::Problem::Spell->new : undef;

    my $need_commit = 0;
    for my $problem (@problems) {
        $current_pid = $problem->{problem_id};
        {
            my $fields_str = join ', ', (qw(
                id title lang difficulty author input_file output_file statement pconstraints json_data run_method),
                'contest_id AS orig_contest_id',
                'max_points AS max_points_def',
                grep(!$problem->{$_}, @cats::limits_fields),
                ($explain ? 'explanation' : qw(input_format output_format)),
                ($is_jury_in_contest && !$p->{noformal} ? 'formal_input' : ()),
            );
            my $p_orig = $dbh->selectrow_hashref(qq~
                SELECT $fields_str FROM problems WHERE id = ?~, { Slice => {} },
                $problem->{problem_id}) or next;
            $problem = { %$problem, %$p_orig };
        }

        $problem->{tags} = $p->{tags} if $is_jury_in_contest && defined $p->{tags};
        $problem->{parsed_tags} = $tags = CATS::Problem::Tags::parse_tag_condition($problem->{tags}, sub {});
        $problem->{lang} = choose_lang($problem, $p, $is_jury_in_contest);
        $problem->{iface_lang} = (grep $_ eq $problem->{lang}, @cats::langs) ? $problem->{lang} : 'en';
        $tags->{lang} = [ 0, $problem->{lang} ];
        $problem->{interactive_io} = $problem->{run_method} != $cats::rm_default;

        if ($is_jury_in_contest && !$p->{nokw}) {
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
        if ($show_points && !$problem->{max_points}) {
            $problem->{max_points} = CATS::RankTable::cache_max_points($problem);
            $need_commit = 1;
        }

        $problem->{samples} = $dbh->selectall_arrayref(qq~
            SELECT rank, in_file, out_file
            FROM samples WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
            $problem->{problem_id});

        $problem->{href_problem_list} =
            ($CATS::StaticPages::is_static_page ? '../' : '') .
            url_function('problems', cid => $problem->{contest_id} || $problem->{orig_contest_id});

        $spellchecker->push_lang($problem->{lang}) if $spellchecker;
        for my $field_name (qw(statement pconstraints input_format output_format explanation)) {
            for ($problem->{$field_name}) {
                defined $_ or next;
                $text_span = '';
                $_ = $_ eq '' ? undef : parse($_) unless $is_root && $p->{raw};
                CATS::TeX::Lite::convert_all($_);
                s/(\s|~)(:?-){2,3}(?!-)/($1 ? '&nbsp;' : '') . '&#8212;'/ge; # em-dash
            }
        }
        $spellchecker->pop_lang if $spellchecker;
        $_ = Encode::decode_utf8($_) for $problem->{json_data};
    }
    $dbh->commit if $need_commit;

    $t->param(
        title_suffix => (@problems == 1 ? $problems[0]->{title} : res_str(524)),
        problems => \@problems,
        tex_styles => CATS::TeX::Lite::styles(),
        mathjax => !$p->{nomath},
    );
}

1;
