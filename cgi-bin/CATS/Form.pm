package CATS::Form;

use strict;
use warnings;

use CATS::DB;
use CATS::Web qw(param url_param);
use CATS::Misc qw($t init_template url_f msg res_str);

use Exporter qw(import);

our @EXPORT = qw(
    validate_string_length
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
    my ($self, $fields_to_template) = @_;
    init_template($self->{templates}->{edit_frame} or die 'No edit frame template');

    my $id = url_param($self->{edit_param});

    my $field_values = $id ? CATS::DB::select_row(
        $self->{table}, [ $self->field_names ], { id => $id }) : {};
    $fields_to_template->($field_values) if $fields_to_template;

    $t->param(
        id => $id,
        %$field_values,
        href_action => url_f($self->{href_action} or die 'No href_action'));
}

sub edit_save {
    my ($self, $template_to_fields) = @_;
    my $params;
    $params->{$_} = param($_) for $self->field_names;
    $template_to_fields->($params) if $template_to_fields;
    my $id = param('id');

    if ($id) {
        $dbh->do(_u $sql->update($self->{table}, $params, { id => $id }));
    }
    else {
        $params->{id} = new_id;
        $dbh->do(_u $sql->insert($self->{table}, $params));
    }
    $dbh->commit;
    1;
}

sub validate_string_length {
    my ($str, $field_name_id, $min, $max) = @_;
    $str //= '';
    return 1 if $min <= length($str) && length($str) <= $max;
    my $fn = res_str($field_name_id);
    $min ? msg(1044, $fn, $min, $max) : msg(1043, $fn, $max);
}

1;
