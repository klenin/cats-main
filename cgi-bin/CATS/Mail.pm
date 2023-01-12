package CATS::Mail;

use strict;
use warnings;

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


    $mailer->auth($s->{login}, $s->{password}) or die $mailer->message;
    $mailer->mail($s->{email}) or die $mailer->message;
    $mailer->to($to) or die $mailer->message;
    $mailer->data or die $mailer->message;
    $mailer->datasend($text) or die $mailer->message;
    $mailer->dataend or die $mailer->message;
    $mailer->quit or die $mailer->message;
}

1;
