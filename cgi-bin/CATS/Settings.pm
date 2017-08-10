package CATS::Settings;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw($settings);

use MIME::Base64;
use Storable qw();

use CATS::DB;
use CATS::Web qw(cookie);

our $settings;

# CATS::Misc depends on CATS::Settings, so can not use global $uid here.
my ($user_id, $enc_settings);

sub init {
    ($user_id, $enc_settings) = @_;
    if (!$user_id) {
        $enc_settings = cookie('settings') || '';
        $enc_settings = decode_base64($enc_settings) if $enc_settings;
    }
    # If any problem happens during the thaw, clear settings.
    $settings = eval { $enc_settings && Storable::thaw($enc_settings) } || {};
}

sub as_cookie {
    my ($lang) = @_;
    $user_id && $lang eq 'ru' ? undef : cookie(
        -name => 'settings',
        -value => encode_base64($user_id ? Storable::freeze({ lang => $lang }) : $enc_settings),
        -expires => '+1h');
}

sub save {
    my $new_enc_settings = Storable::freeze($settings);
    $new_enc_settings ne ($enc_settings || '') or return;
    $enc_settings = $new_enc_settings;
    $user_id or return; # Cookie only for anonymous users.
    $dbh->commit;
    $dbh->do(q~
        UPDATE accounts SET settings = ? WHERE id = ?~, undef,
        $new_enc_settings, $user_id);
    $dbh->commit;
}

1;
