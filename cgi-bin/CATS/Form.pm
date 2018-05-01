package CATS::Form;

use strict;
use warnings;

use CATS::DB;
use CATS::Globals qw($t);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::Web qw(param url_param);

use Exporter qw(import);

our @EXPORT = qw(
    validate_string_length
    validate_integer
);

sub new {
    my ($class, $self) = @_;
    $self->{table} or die 'No table';
    $self->{fields} or die 'No fields';
    $self->{edit_param} ||= 'edit';
    for (@{$self->{fields}}) {
        $_->{name} or die;
    }
    bless $self, $class;
}

sub field_names { sort map $_->{name}, @{$_[0]->{fields}} }

# Params: opts { after, href_action_params }
sub edit_frame {
    my ($self, %opts) = @_;
    init_template($self->{templates}->{edit_frame} or die 'No edit frame template');

    my $id = url_param($self->{edit_param});

    my $field_values = $id ? CATS::DB::select_row(
        $self->{table}, [ $self->field_names ], { id => $id }) : {};
    $field_values->{id} //= $id;
    $opts{after}->($field_values) if $opts{after};

    $self->{href_action} or die 'No href_action';
    $t->param(
        id => $id,
        %$field_values,
        href_action => url_f($self->{href_action}, @{$opts{href_action_params} || []}),
    );
}

# Params: opts { before }
sub edit_save {
    my ($self, %opts) = @_;
    my $params;
    $params->{$_} = param($_) for $self->field_names;
    $opts{before}->($params) if $opts{before};
    my $id = param('id');

    my ($stmt, @bind) = $id ?
        $sql->update($self->{table}, $params, { id => $id }) :
        $sql->insert($self->{table}, { %$params, id => new_id });
    warn "$stmt\n@bind" if $self->{debug};
    $dbh->do($stmt, undef, @bind);
    $dbh->commit;
    1;
}

# Params: opts { id, descr, msg, before_commit }
sub edit_delete {
    my ($self, %opts) = @_;
    $opts{id} or return;
    $opts{descr} //= 1;
    if (my ($descr) = $dbh->selectrow_array(_u $sql->select(
        $self->{table}, [ $opts{descr} // 1 ], { id => $opts{id} }))
    ) {
        $dbh->do(_u $sql->delete($self->{table}, { id => $opts{id} }));
        $opts{before_commit}->() if $opts{before_commit};
        $dbh->commit;
        msg($opts{msg}, $descr) if $opts{msg};
    }
}

sub validate_string_length {
    my ($str, $field_name_id, $min, $max) = @_;
    $str //= '';
    return 1 if $min <= length($str) && length($str) <= $max;
    my $fn = res_str($field_name_id);
    $min ? msg(1044, $fn, $min, $max) : msg(1043, $fn, $max);
}

# Params: p { allow_empty, min, max }
sub validate_integer {
    my ($str, $field_name_id, %p) = @_;
    defined $p{min} && defined $p{max} or die;
    if ($str) {
        return 1 if $str =~ /^\d+$/ && $p{min} <= $str && $str <= $p{max};
    }
    elsif ($p{allow_empty}) {
        return 1;
    }
    msg(1045, res_str($field_name_id), $p{min}, $p{max});
}

1;
