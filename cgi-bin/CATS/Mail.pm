package CATS::Mail;

use strict;
use warnings;

use Authen::SASL;
use Net::SMTP::SSL;

use CATS::Config;

# opts: verbose
sub send {
    my ($to, $text, %opts) = @_;
    my $s = $CATS::Config::smtp;

    my $mailer = Net::SMTP::SSL->new(
        $s->{server},
        Hello => $s->{server},
        Port => $s->{port},
        Debug => $opts{verbose},
    ) or die $@ || 'SMTP initialization failed';

    # Remove in Perl 2.24+.
    # https://stackoverflow.com/questions/45284306/perl-netsmtp-force-auth-method
    my $auth = Authen::SASL->new(
        mechanism => 'LOGIN PLAIN CRAM-MD5', # GSSAPI
        callback  => { user => $s->{login}, pass => $s->{password} },
        debug => $opts{verbose},
    );
    {
        no warnings 'redefine';
        my $count;
        local *Authen::SASL::mechanism = sub {
            my $self = shift;

            # Fix Begin
            # ignore first setting of mechanism
            if ( !$count++ && @_ && $Net::SMTP::VERSION =~ /^2\./ ) {
                return;
            }

            # Fix End
            @_ ? $self->{mechanism} = shift : $self->{mechanism};
        };

        $mailer->auth($auth) or die $mailer->message;
    }
    $mailer->mail($s->{email}) or die $mailer->message;
    $mailer->to($to) or die $mailer->message;
    $mailer->data or die $mailer->message;
    $mailer->datasend($text) or die $mailer->message;
    $mailer->dataend or die $mailer->message;
    $mailer->quit or die $mailer->message;
}

1;
