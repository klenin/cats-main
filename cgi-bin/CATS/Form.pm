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

sub edit_frame {
    my ($self, $fields_to_template, %p) = @_;
    init_template($self->{templates}->{edit_frame} or die 'No edit frame template');

    my $id = url_param($self->{edit_param});

    my $field_values = $id ? CATS::DB::select_row(
        $self->{table}, [ $self->field_names ], { id => $id }) : {};
    $fields_to_template->($field_values) if $fields_to_template;

    $self->{href_action} or die 'No href_action';
    $t->param(
        id => $id,
        %$field_values,
        href_action => url_f($self->{href_action}, @{$p{href_action_params} || []}),
    );
}

sub edit_save {
    my ($self, $template_to_fields) = @_;
    my $params;
    $params->{$_} = param($_) for $self->field_names;
    $template_to_fields->($params) if $template_to_fields;
    my $id = param('id');

    my ($stmt, @bind) = $id ?
        $sql->update($self->{table}, $params, { id => $id }) :
        $sql->insert($self->{table}, { %$params, id => new_id });
    warn "$stmt\n@bind" if $self->{debug};
    $dbh->do($stmt, undef, @bind);
    $dbh->commit;
    1;
}

# Params: id, descr, msg, before_commit
sub edit_delete {
    my ($self, %p) = @_;
    $p{id} or return;
    $p{descr} //= 1;
    if (my ($descr) = $dbh->selectrow_array(_u $sql->select(
        $self->{table}, [ $p{descr} // 1 ], { id => $p{id} }))
    ) {
        $dbh->do(_u $sql->delete($self->{table}, { id => $p{id} }));
        $p{before_commit}->() if $p{before_commit};
        $dbh->commit;
        msg($p{msg}, $descr) if $p{msg};
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
