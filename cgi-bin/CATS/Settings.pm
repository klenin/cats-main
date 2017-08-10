package CATS::Settings;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw($settings);

use Data::Dumper;
use Encode qw();
use MIME::Base64;
use Storable qw();

use CATS::Constants;
use CATS::DB;
use CATS::Misc qw($uid);
use CATS::Web qw(param cookie);

our $settings;

my $enc_settings;

sub init {
    ($enc_settings) = @_;
    if (!$uid) {
        $enc_settings = cookie('settings') || '';
        $enc_settings = decode_base64($enc_settings) if $enc_settings;
    }
    # If any problem happens during the thaw, clear settings.
    $settings = eval { $enc_settings && Storable::thaw($enc_settings) } || {};

    my $lang = param('lang');
    $settings->{lang} = $lang if $lang && grep $_ eq $lang, @cats::langs;
}

sub lang { $settings->{lang} || 'ru' }

sub as_cookie {
    $uid && lang() eq 'ru' ? undef : cookie(
        -name => 'settings',
        -value => encode_base64($uid ? Storable::freeze({ lang => lang() }) : $enc_settings),
        -expires => '+1h');
}

sub save {
    my $new_enc_settings = Storable::freeze($settings);
    $new_enc_settings ne ($enc_settings || '') or return;
    $enc_settings = $new_enc_settings;
    $uid or return; # Cookie only for anonymous users.
    $dbh->commit;
    $dbh->do(q~
        UPDATE accounts SET settings = ? WHERE id = ?~, undef,
        $new_enc_settings, $uid);
    $dbh->commit;
}

sub _apply_rec {
    my ($val, $sub) = @_;
    ref $val eq 'HASH' ?
        { map { $_ => _apply_rec($val->{$_}, $sub) } keys %$val } :
        $sub->($val);
}

sub as_dump {
    my ($s) = @_;
    # Data::Dumper escapes UTF-8 characters into \x{...} sequences.
    # Work around by dumping encoded strings, then decoding the result.
    my $d = Data::Dumper->new([ _apply_rec($s, \&Encode::encode_utf8) ]);
    $d->Quotekeys(0);
    $d->Sortkeys(1);
    Encode::decode_utf8($d->Dump);
}

1;
