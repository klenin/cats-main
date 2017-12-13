package CATS::Problem::Spell;

use strict;
use warnings;

use Encode;
use Text::Aspell;

sub new {
    my ($class) = @_;
    bless {
        checkers => {},
        langs => [],
    }, $class;
}

sub push_lang { push @{$_[0]->{langs}}, $_[1] }
sub pop_lang { pop @{$_[0]->{langs}} }

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
    # Aspell currently supports only KOI8-R russian encoding.
    my $koi = Encode::encode('KOI8-R', $word);
    my $lang = $self->{langs}->[-1] or die;
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
