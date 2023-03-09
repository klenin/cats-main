package CATS::Problem::Spell;

use strict;
use warnings;

use Encode;
use File::Spec;

use CATS::Config;

my $known_langs = { ru => 'ru_RU', en => 'en_US' };

sub _hunspell_dict_files {
    map File::Spec->catdir($CATS::Config::spellcheck_dir, "$_[0].$_"), 'aff', 'dic' }

sub _check_hunspell_dicts {
    for (values %$known_langs) {
        2 == grep -f, _hunspell_dict_files($_) or return;
    }
    1;
}

my $spell_module;
BEGIN {
    # Neither Text::Aspell nor Text::Hunspell can change options of the existing object,
    # so create a new one per language.
    my $spell_modules = {
        hunspell => {
            make => sub {
                Text::Hunspell->new(_hunspell_dict_files($_[0]));
            },
        },
        aspell => {
            make => sub {
                my $spellchecker = Text::Aspell->new;
                $spellchecker->set_option(lang => $_[0]);
                $spellchecker->set_option(encoding => 'UTF-8');
                $spellchecker;
            },
        },
        none => {
            make => sub {},
        },
    };

    $spell_module = $spell_modules->{
        eval { require Text::Hunspell; } && _check_hunspell_dicts() ? 'hunspell' :
        eval { require Text::Aspell; } ? 'aspell' :
        'none'};
}

sub new {
    my ($class) = @_;
    bless {
        checkers => {},
        dicts => {},
        dict_depth => 0,
        langs => [],
    }, $class;
}

sub lang { $_[0]->{langs}->[-1] // die }

sub push_lang {
    my ($self, $lang, $dict) = @_;
    push @{$self->{langs}}, $lang // $self->lang;
    if ($self->{dict_depth}) {
        $self->{dict_depth}++;
    }
    else {
        $self->{dict_depth} = 1 if $dict;
    }
}

sub pop_lang {
    my ($self) = @_;
    pop @{$self->{langs}};
    $self->{dict_depth}-- if $self->{dict_depth};
}

my $checkers = {};

sub _make_checker {
    my ($self, $lang) = @_;
    my $kl = $known_langs->{$lang} or return;
    $spell_module->{'make'}->($kl);
}

sub check_word {
    my ($self, $word) = @_;
    # The '_' character causes SIGSEGV (!) inside of ASpell.
    return $word if $word =~ /(?:\d|_)/;
    $word =~ s/\x{AD}//g; # Ignore soft hypens.
    my $lang = $self->lang;

    return $word if $self->{$lang}->{dicts}->{lc $word};
    if ($self->{dict_depth}) {
        $self->{$lang}->{dicts}->{lc $word} = 1;
        return $word;
    }

    my $checker = $checkers->{$lang} //= $self->_make_checker($lang)
        or return $word;
    return $word if $checker->check($word);
    my $suggestion = Encode::decode_utf8(
        join ' | ', grep $_, ($checker->suggest($word))[0..9]);
    return qq~<span class="spell" title="$suggestion">$word</span>~;
}

# Check $_, add hints for unknown words.
sub check_topicalizer {
    # Ignore entities, count apostrophe as part of word except in the beginning of word.
    s/(?<!(?:\w|&))(\w(?:\w|\'|\x{AD})*)/$_[0]->check_word($1)/eg;
}

1;
