package CATS::DevEnv;

use strict;
use warnings;

use fields qw(_de_list _dbh);

use CATS::Utils;


sub new
{
    my ($self, $dbh, %p) = @_;
    $self = fields::new($self) unless ref $self;
    $self->{_de_list} = [];
    $self->{_dbh} = $dbh;
    $self->load(%p);
    return $self;
}


sub load
{
    (my CATS::DevEnv $self, my %p) = @_;
    my $where = $p{active_only} ? 'WHERE in_contests=1' : '';
    $self->{_de_list} = $self->{_dbh}->selectall_arrayref(qq~
        SELECT id, code, description, file_ext FROM default_de
        $where ORDER BY code~, { Slice => {} });
}


sub by_file_extension
{
    (my CATS::DevEnv $self, my $file_name) = @_;

    my (undef, undef, undef, undef, $ext) = CATS::Utils::split_fname(lc $file_name);

    for my $de (@{$self->{_de_list}})
    {
        grep { return $de if $_ eq $ext } split(/\;/, $de->{file_ext});
    }

    return undef;
}


sub by_code
{
    (my CATS::DevEnv $self, my $code) = @_;
    my @r = grep $_->{code} eq $code, @{$self->{_de_list}};
    return @r ? $r[0] : undef;
}


1;
