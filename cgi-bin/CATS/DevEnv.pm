package CATS::DevEnv;

use strict;
use warnings;

use fields qw(_de_list _dbh);

use CATS::Utils;
use CATS::DB;

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
    $self->{_de_list} = $self->{_dbh}->selectall_arrayref(
        _u $sql->select('default_de', 'id, code, description, file_ext', {
            ($p{active_only} ? (in_contests => 1) : ()),
            ($p{id} ? (id => $p{id}) : ()),
        }, 'code'));
}


sub split_exts { split /\;/, $_[0]->{file_ext} }

sub by_file_extension
{
    (my CATS::DevEnv $self, my $file_name) = @_;
    $file_name or return;

    my (undef, undef, undef, undef, $ext) = CATS::Utils::split_fname(lc $file_name);

    for my $de (@{$self->{_de_list}})
    {
        grep { return $de if $_ eq $ext } split_exts($de);
    }

    undef;
}


sub by_code
{
    (my CATS::DevEnv $self, my $code) = @_;
    my @r = grep $_->{code} eq $code, @{$self->{_de_list}};
    @r ? $r[0] : undef;
}


sub by_id
{
    (my CATS::DevEnv $self, my $id) = @_;
    my @r = grep $_->{id} eq $id, @{$self->{_de_list}};
    @r ? $r[0] : undef;
}


sub default_extension
{
    (my CATS::DevEnv $self, my $id) = @_;
    (split_exts($self->by_id($id) // ('txt')))[0];
}


1;
