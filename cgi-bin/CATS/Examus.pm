package CATS::Examus;

use strict;
use warnings;

use Digest::SHA qw(hmac_sha256);
use HTTP::Request::Common;
use JSON::XS;
use MIME::Base64 qw(encode_base64url);

use CATS::Config;
use CATS::Globals qw($cid $sid);
use CATS::Utils qw(date_to_iso);
use CATS::Output qw(url_f);

sub new {
    my ($class, %p) = @_;
    my $self = {
        #agent => LWP::UserAgent->new(requests_redirectable => [ qw(GET POST) ]),
        examus_url => $p{examus_url} || 'stage.examus.net',
        integration_name => $p{integration_name} || 'nto',
        secret => $p{secret} || die('No secret'),
        verbose => $p{verbose},
        contest_id => $cid,
        session_id => $sid,
        start_date => $p{start_date} || die('No start_date'),
        finish_date => $p{finish_date} || die('No finish_date'),
    };
    bless $self => $class;
}

sub false { JSON::XS::false }
sub true { JSON::XS::true }

sub _date_fmt {
    $_[0] =~ /^\s*(\d+)\.(\d+)\.(\d+)\s+(\d+):(\d+)\s*$/;
    "$3-$2-$1T$4:${5}:00" . sprintf '%+02d', $CATS::Config::timezone_offset;
}

sub _payload {
    my ($self) = @_;
    return {
    userId => "1232134",
    lastName => "Иванов",
    firstName => "Иван",
    thirdName => "Иванович",
    language => "ru",
    accountId => 123,
    accountName => "ДВФУ",
    examId => $self->{contest_id},
    courseName => "НТО",
    examName => "Олимпиада",
    userAgreementUrl => "https://dvfu.ru",
    duration => 120,
    schedule => false,
    auxiliaryCamera => false,
    proctoring => "offline",
    identification => "face",
    rules => {
        allow_to_use_paper => true,
        allow_to_use_calculator => false
    },
    startDate => _date_fmt($self->{start_date}),
    endDate => _date_fmt($self->{finish_date}),
    sessionId => $self->{session_id},
    sessionUrl => $CATS::Config::absolute_url . url_f('problems'),
    exp => time() + 30,
    biometricIdentification => {
        enabled => false,
        #photo_url => "https://example.org/face.png",
        #skip_fail => false,
        #flow => "test-flow"
    },
    scoreConfig => {
        cheaterLevel => 80,
        extraUserInFrame => 1.0,
        substitutionUser => 1.0,
        noUserInFrame => 1.0,
        avertEyes => 1.0,
        changeActiveWindowOnComputer => 0.0,
        forbiddenDevice => 1.0,
        voiceDetected => 1.0,
        phone => 1.0
    },
    visibleWarnings => {
        warning_extra_user_in_frame => false,
        warning_timeout => false,
        warning_change_active_window_on_computer => false,
    }
    }
}

sub _jws_header() { '{"typ":"JWT","alg":"HS256"}' }

sub payload { encode_json($_[0]->_payload) }

sub make_jws_token {
    my ($self) = @_;
    my $payload = encode_base64url(encode_json($self->_payload));
    my $header = encode_base64url(_jws_header);
    my $sig = encode_base64url(hmac_sha256("$header.$payload", $self->{secret}));
    "$header.$payload.$sig";
}

sub start_session_url {
    my ($self) = @_;
    "https://$self->{examus_url}/integration/simple/$self->{integration_name}/start/";
}

1;
