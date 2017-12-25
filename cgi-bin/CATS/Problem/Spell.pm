package CATS::Problem::Spell;

use strict;
use warnings;

use Encode;
use Text::Aspell;

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

my $known_langs = { ru => 'ru_RU', en => 'en_US' };

sub _make_checker {
    my ($self, $lang) = @_;
    my $kl = $known_langs->{$lang} or return;
    # Per Text::Aspell docs, we cannot change options of the existing object,
    # so create a new one per language.
    my $spellchecker = Text::Aspell->new;
    $spellchecker->set_option('lang', $kl);
    $spellchecker;
}

sub check_word {
    my ($self, $word) = @_;
    # The '_' character causes SIGSEGV (!) inside of ASpell.
    return $word if $word =~ /(?:\d|_)/;
    $word =~ s/\x{AD}//g; # Ignore soft hypens.
    my $lang = $self->lang;

    return $word if $self->{$lang}->{dicts}->{$word};
    if ($self->{dict_depth}) {
        $self->{$lang}->{dicts}->{$word} = 1;
        return $word;
    }

    # Aspell currently supports only KOI8-R russian encoding.
    my $koi = Encode::encode('KOI8-R', $word);
    my $checker = $self->{checkers}->{$lang} //= $self->_make_checker($lang)
        or return $word;
    return $word if $checker->check($koi);
    my $suggestion = Encode::decode('KOI8-R',
        join ' | ', grep $_, ($checker->suggest($koi))[0..9]);
    return qq~<a class="spell" title="$suggestion">$word</a>~;
}

# Check $_, add hints for unknown words.
sub check_topicalizer {
    # Ignore entities, count apostrophe as part of word except in the beginning of word.
    s/(?<!(?:\w|&))(\w(?:\w|\'|\x{AD})*)/$_[0]->check_word($1)/eg;
}

1;
