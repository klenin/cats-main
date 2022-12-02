use strict;
use warnings;

package CATS::Field;

use Encode;

use CATS::DB;
use CATS::Messages qw(msg res_str);

sub new {
    my ($class, %r) = @_;
    bless my $self = {}, $class;
    $self->{name} = $r{name} or die;
    $self->{db_name} = $r{db_name} || $r{name};
    $self->{caption} = $r{caption} || $r{name};
    $self->{validators} = $r{validators} // [];
    ref $self->{validators} eq 'ARRAY' or $self->{validators} = [ $self->{validators} ];
    $self->{$_} = $r{$_} for qw(after_load after_parse before_save default editor);
    $self;
}

sub web_data {
    my ($self, $value, $error) = @_;
    { field => $self, value => $value, error => $error, caption => $self->caption_res };
}

sub caption_res { $_[0]->{caption} =~ /^\d+$/ ? res_str($_[0]->{caption}) : '' }
sub caption_msg { $_[0]->caption_res || $_[0]->{name} }

sub parse_web_param {
    my ($self, $p) = @_;
    my $value = $p->{$self->{name}};
    $value = $self->{after_parse}->($value, $p) if $self->{after_parse};
    $self->web_data($value, $self->validate($value));
}

sub validate {
    my ($self, $value) = @_;
    for my $v (@{$self->{validators}}) {
        $v or die "Empty validator for '$self->{name}'";
        if (ref $v eq 'CODE') {
            my $error = $v->($value, $self);
            return $error if $error;
        }
        elsif (($value // '') !~ $v) {
            return res_str(1198, $self->caption_msg, $v);
        }
    }
}

sub default {
    my ($self) = @_;
    return !defined($_) ? '' : ref $_ eq 'CODE' ? $_->() : $_ for $self->{default};
}

sub load {
    my ($self, $value) = @_;
    $self->{after_load} ? $self->{after_load}->($value) : $value;
}

sub save {
    my ($self, $value) = @_;
    $self->{before_save} ? $self->{before_save}->($value) : $value;
}

sub str_length {
    my ($min, $max) = @_;
    sub {
        my ($value, $field) = @_;
        # Firebird measures field length in bytes, not characters.
        $value = Encode::encode_utf8($value // '');
        return if $min <= length($value) && length($value) <= $max;
        my $fn = $field->caption_msg;
        $min ? res_str(1044, $fn, $min, $max) : res_str(1043, $fn, $max);
    };
}

# Params:{ allow_empty, min, max }
sub int_range {
    my (%opts) = @_;
    defined $opts{min} && defined $opts{max} or die;
    sub {
        my ($value, $field) = @_;
        if (($value // '') ne '') {
            return if $value =~ /^-?\d+$/ && $opts{min} <= $value && $value <= $opts{max};
        }
        elsif ($opts{allow_empty}) {
            return;
        }
        res_str(1045, $field->caption_msg, $opts{min}, $opts{max});
    };
}

# Params:{ allow_empty, min, max }
sub fixed {
    my (%opts) = @_;
    sub {
        my ($value, $field) = @_;
        if (($value // '') ne '') {
            return if $value =~ /^-?\d+(\.\d+)?$/ &&
                (!defined $opts{min} || $opts{min} <= $value) &&
                (!defined $opts{max} || $value <= $opts{max});
        }
        elsif ($opts{allow_empty}) {
            return;
        }
        res_str(1051, $field->caption_msg, $opts{min} // '-Inf', $opts{max} // '+Inf');
    };
}

sub _in_range { $_[1] <= $_[0] && $_[0] <= $_[2] }
my @month_days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
sub _is_leap { $_[0] % 4 == 0 && ($_[0] % 100 != 0 || $_[0] % 400 == 0) }

# Params:{ allow_empty }
sub date_time {
    my (%opts) = @_;
    sub {
        my ($value, $field) = @_;
        return $opts{allow_empty}  ? undef : res_str(1052, $field->caption_msg)
            if ($value // '') eq '';
        my ($day, $month, $year, $hour, $minute) =
            $value =~ /^\s*(\d+)\.(\d+)\.(\d+)(?:\s*(\d+):(\d+)\s*)?$/;
        $day &&
        _in_range($month, 1, 12) &&
        _in_range($day, 1, $month_days[$month - 1] + ($month == 2 && _is_leap($year) ? 1 : 0)) &&
        _in_range($year, 1, 9999) &&
        (!$hour || _in_range($hour, 0, 23)) &&
        (!$minute || _in_range($minute, 0, 59))
            or return res_str(1052, $field->caption_msg);
        undef;
    };
}

sub unique {
    my ($field) = @_;
    $field or die;
    sub {
        my ($fd, $p) = @_;
        my $f = $fd->{indexed}->{$field} or die;
        $f->{value} or return 1;
        my @id_cond = $fd->{id} ? ('id' => { '!=', $fd->{id} }) : ();
        my $conflicts = $dbh->selectall_arrayref(_u $sql->select($fd->{form}->{table},
            'id', { $f->{field}->{db_name} => $f->{value}, @id_cond }
        )) or return 1;
        @$conflicts or return 1;
        $f->{error} = res_str(1197, $f->{field}->caption_msg);
        undef;
    };
}

sub foreign_key { int_range(min => 1, max => 2e9, @_) }
our $foreign_key = foreign_key;
our $foreign_key_opt = foreign_key(allow_empty => 1);
our $bool = int_range(min => 0, max => 1, allow_empty => 1);
our $date_time_req = date_time;
our $date_time = date_time(allow_empty => 1);
our %default_zero = (before_save => sub { $_[0] // 0 });

package CATS::Form;

use CATS::DB;
use CATS::Globals qw($t);
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::RouteParser;

use Exporter qw(import);

our @EXPORT = qw(
    validate_fixed_point
    validate_integer
    validate_string_length
);

sub _extract_field_name {
    $_[0] =~ /(?:\w+\.)?(\w+)(?:\s+AS\s+(\w+))?$/ or die;
    $2 // $1;
}

sub new {
    my ($class, %r) = @_;
    bless my $self = {}, $class;

    $self->{$_} = $r{$_} or die "No $_" for qw(table);
    if ($self->{table} =~ /\s+(\w+)$/) {
        $self->{table_alias} = $1;
    }
    $self->{joins} = $r{joins} // [];
    $r{fields} or die 'No fields';
    $self->{fields} = [ map ref $_ eq 'CATS::Field' ? $_ : CATS::Field->new(@$_), @{$r{fields}} ];
    my $alias = $self->{table_alias} ? "$self->{table_alias}." : '';
    $self->{sql_fields} = [ map "$alias$_->{db_name}", $self->fields ];
    my @all_extra_fields = map ref $_->{fields} ? @{$_->{fields}} : $_->{fields}, @{$self->{joins}};
    $self->{extra_fields} = [ map +{ sql => $_, name => _extract_field_name($_) }, @all_extra_fields ];
    $self->{select_fields} = [ @{$self->{sql_fields}}, @all_extra_fields ];
    $self->{id_param} = $r{id_param} // 'id';
    $self->{template_var} = $r{template_var} // 'form_data';
    $self->{descr_field} = $r{descr_field} // 'id';
    $self->{validators} = $r{validators} // [];
    $self->{$_} = $r{$_} for qw(
        after_delete after_load after_make after_save
        before_commit before_delete before_display before_save before_save_db
        debug href_action msg_deleted msg_saved
        override_get_id override_load override_save
        redirect redirect_cancel redirect_save
    );
    $self;
}

sub fields { @{$_[0]->{fields}} }

sub fields_sql { join ', ', @{$_[0]->{select_fields}} }

sub load {
    my ($self, $id) = @_;
    return $self->{override_load}->($self, $id) if $self->{override_load};
    my $id_field = $self->{table_alias} ? "$self->{table_alias}.id" : 'id';
    my @db_data = $dbh->selectrow_array(_u $sql->select(
        $self->{table} . join('', map " $_->{sql}", @{$self->{joins}}),
        $self->{select_fields}, { $id_field => $id }));
    my $i = 0;
    [
        (map +$_->load($db_data[$i++]), $self->fields),
        (map $db_data[$i++], @{$self->{extra_fields}}),
    ];
}

# Params: opts { debug, commit }
sub save {
    my ($self, $id, $data, %opts) = @_;
    return $self->{override_save}->($self, $id, $data, %opts) if $self->{override_save};
    my $i = 0;
    my $db_data = { map { $_->{db_name} => $_->save($data->[$i++]) } $self->fields };
    $self->{before_save_db}->($db_data, $id, $self) if $self->{before_save_db};
    # INSERT does not support table aliases.
    my ($bare_table) = $self->{table} =~ /^(\w+)/;
    my ($stmt, @bind) = $id ?
        $sql->update($bare_table, $db_data, { id => $id }) :
        $sql->insert($bare_table, { %$db_data, id => ($id = new_id) });
    warn "$stmt\n@bind" if $self->{debug} || $opts{debug};
    $dbh->do($stmt, undef, @bind);
    if ($opts{commit}) {
        $self->{before_commit}->($self) if $self->{before_commit};
        $dbh->commit;
    }
    $id;
}

sub make {
    my ($self) = @_;
    [ map $_->default, $self->fields ];
}

sub route {
    my ($self) = @_;
    (id => integer, edit_save => bool, edit_cancel => bool, $self->route_fields);
}

sub route_fields {
    my ($self) = @_;
    # Validation is performed after routing.
    (map { $_->{name} => undef } $self->fields);
}

sub parse_params {
    my ($self, $p) = @_;
    [ map $_->parse_web_param($p), $self->fields ];
}

sub _set_form_data {
    my ($form_data, $ordered) = @_;
    $form_data->{ordered} = $ordered;
    $form_data->{indexed} = { map { $_->{field}->{name} => $_ } @$ordered };
    $form_data;
}

sub parse_form_data {
    my ($self, $p) = @_;
    _set_form_data({}, $self->parse_params($p));
}

sub _redirect {
    my ($p, $redirect, @params) = @_;
    $p->redirect(url_f @$redirect, @params) if $redirect;
}

sub validate {
    my ($self, $form_data, $p) = @_;
    for (@{$self->{validators}}) {
        $_->($form_data, $p) or return;
    }
    1;
}

sub _href_action {
    my ($self, $form_data, $id, $params) = @_;
    $self->{href_action} or return;
    $form_data->{href_action} =  url_f($self->{href_action}, $self->{id_param} => $id, @{$params || []});
}

# Params: opts { href_action_params, readonly, redirect, redirect_cancel, redirect_save }
sub edit_frame {
    my ($self, $p, %opts) = @_;

    my %redir = map {
        $_ => $opts{"redirect_$_"} // $opts{redirect} // $self->{"redirect_$_"} // $self->{redirect}
    } qw(cancel save);
    return _redirect($p, $redir{cancel}) if $p->{edit_cancel};

    my $id = $self->{override_get_id} ? $self->{override_get_id}->($self, $p) : $p->{$self->{id_param}};
    my $form_data = {
        form => $self,
        readonly => $opts{readonly},
        $self->{id_param} => $id,
    };
    $self->_href_action($form_data, $id, $opts{href_action_params});
    $t and $t->param($self->{template_var} => $form_data);
    if ($p->{edit_save} && !$opts{readonly}) {
        _set_form_data($form_data, my $data = $self->parse_params($p));
        if ((grep $_->{error}, @$data) || !$self->validate($form_data, $p)) {
            $self->{before_display}->($form_data, $p) if $self->{before_display};
            return;
        }
        $self->{before_save}->($form_data, $p) if $self->{before_save};
        $form_data->{$self->{id_param}} = $id =
            $self->save($id, [ map $_->{value}, @$data ], commit => 1);
        $self->{after_save}->($form_data, $p) if $self->{after_save};
        if (my $rs = $redir{save}) {
            return _redirect($p,
                ref $rs eq 'CODE' ? $rs->($form_data, $p) : $rs, saved => $id);
        }
        $self->_href_action($form_data, $id, $opts{href_action_params});
        if ($self->{msg_saved} && (my $d = $self->{descr_field})) {
            my @descr = $d =~ m/^\w+$/ && $form_data->{indexed}->{$d} ?
                ($form_data->{indexed}->{$d}->{value}) :
                $dbh->selectrow_array(_u $sql->select($self->{table}, $d, { id => $id }));
            msg($self->{msg_saved}, @descr);
        }
    }
    else {
        my $data = $id ? $self->load($id) : $self->make;
        my $i = 0;
        _set_form_data($form_data, [ map $_->web_data($data->[$i++]), $self->fields ]);
        $form_data->{extra_fields} = $id ?
            { map { +$_->{name} => $data->[$i++] } @{$self->{extra_fields}} } : {};
        $self->{after_load}->($form_data, $p) if $self->{after_load} && $id;
        $self->{after_make}->($form_data, $p) if $self->{after_make} && !$id;
    }
    $self->{before_display}->($form_data, $p) if $self->{before_display};
    undef;
}

# Params: opts { before_commit }
sub delete_or_saved {
    my ($self, $p, %opts) = @_;
    my $id = $p->{delete} || $p->{saved} or return;
    my @descr = $dbh->selectrow_array(_u $sql->select(
        $self->{table}, $self->{descr_field}, { id => $id })) or return;
    if ($p->{delete}) {
        if ($self->{before_delete}) {
            $self->{before_delete}->($p, $id, descr => \@descr) or return;
        }
        eval {
            $dbh->do(_u $sql->delete($self->{table}, { id => $id }));
        };
        if (my $err = $@) {
            my $ref_table = $CATS::DB::db->foreign_key_violation($err);
            return $ref_table ? msg(1201, $ref_table, @descr) : CATS::Messages::msg_debug($err);
        }
        $self->{after_delete}->($p, $id, descr => \@descr) if $self->{after_delete};
        $opts{before_commit}->($self) if $opts{before_commit};
        $dbh->commit;
        msg($self->{msg_deleted}, @descr) if $self->{msg_deleted};
    }
    if ($p->{saved}) {
        msg($self->{msg_saved}, @descr) if $self->{msg_saved};
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

sub validate_fixed_point {
    my ($str, $field_name_id, %p) = @_;
    if ($str) {
        return 1 if $str =~ /^[+|-]?\d+(\.\d*)?$/;
    }
    elsif ($p{allow_empty}) {
        return 1;
    }
    msg(1049, res_str($field_name_id));
}
