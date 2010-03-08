package CATS::Problem;

use strict;
use warnings;


sub apply_test_rank
{
    my ($v, $rank) = @_;
    defined $v && $rank or return $v;
    #$v = '' unless defined $v;
    $v =~ s/%n/$rank/g;
    $v =~ s/%0n/sprintf("%02d", $rank)/eg;
    $v =~ s/%%/%/g;
    $v;
}


sub validate_test
{
    my ($test) = @_;
    defined $test->{in_file} || $test->{generator_id}
        or return 'No input source';
    defined $test->{in_file} && $test->{generator_id}
        and return 'Both input file and generator';
    (defined $test->{param} && $test->{param} ne '' || $test->{gen_group}) && !$test->{generator_id}
        and return 'Parameters without generator';
    defined $test->{out_file} || $test->{std_solution_id}
        or return 'No output source';
    defined $test->{out_file} && $test->{std_solution_id}
        and return 'Both output file and standard solution';
    undef;
}


sub set_test_attr
{
    (my CATS::Problem $self, my $test, my $attr, my $value) = @_;
    defined $value or return;
    defined $test->{$attr}
        and return $self->error("Redefined attribute '$attr' for test #$test->{rank}");
    $test->{$attr} = $value;
}


sub add_test
{
    (my CATS::Problem $self, my $atts, my $rank) = @_;
    $rank =~ /^\d+$/ && $rank > 0 && $rank < 1000
        or $self->error("Bad rank: '$rank'");
    my $t = $self->{tests}->{$rank} ||= { rank => $rank };
    $self->set_test_attr($t, 'points', $atts->{points});
    push @{$self->{current_tests}}, $t;
}


sub parse_test_rank
{
    (my CATS::Problem $self, my $rank_spec) = @_;
    my $result = [];
    # Последовательность диапазонов через запятую, например '1,5-10,2'
    for (split ',', $rank_spec)
    {
        $_ =~ /^\s*(\d+)(?:-(\d+))?\s*$/
            or $self->error("Bad element '$_' in rank spec '$rank_spec'");
        my ($from, $to) = ($1, $2 || $1);
        $from <= $to or $self->error("from > to in rank spec '$rank_spec'");
        push @$result, ($from..$to);
    }
    $result;
}


sub start_tag_Test
{
    (my CATS::Problem $self, my $atts) = @_;
    if ($atts->{rank} eq '*') #=~ /^\s*\*\s*$/)
    {
        $self->{current_tests} = [ $self->{test_defaults} ||= {} ];
        $self->set_test_attr($self->{test_defaults}, 'points', $atts->{points});
    }
    else
    {
        $self->{current_tests} = [];
        $self->add_test($atts, $_) for @{$self->parse_test_rank($atts->{rank})};
    }
}


sub start_tag_TestRange
{
    (my CATS::Problem $self, my $atts) = @_;
    $atts->{from} <= $atts->{to}
        or $self->error('TestRange.from > TestRange.to');
    $self->{current_tests} = [];
    $self->add_test($atts, $_) for ($atts->{from}..$atts->{to});
    $self->warning("Deprecated tag 'TestRange', use 'Test' instead");
}


sub end_tag_Test
{
    my CATS::Problem $self = shift;
    undef $self->{current_tests};
}


sub do_In_src
{
    my ($self, $test, $attr) = @_;
    my $src = apply_test_rank($attr, $test->{rank});
    my $member = $self->{zip}->memberNamed($src)
        or $self->error("Invalid test input file reference: '$src'");
    ('in_file', $self->read_member($member, $self->{debug}));
}


sub do_In_param { ('param', apply_test_rank($_[2], $_[1]->{rank})) }


sub do_In_use
{
    my ($self, $test, $attr) = @_;
    my $use = apply_test_rank($attr, $test->{rank});
    ('generator_id', $self->get_imported_id($use) || $self->get_named_object($use)->{id});
}


sub do_In_genAll
{
    my ($self, $test, $attr) = @_;
    my $gg = $self->{gen_groups};
    ('gen_group', $gg->{$test->{generator_id}} ||= 1 + keys %$gg);
}


sub start_tag_In
{
    (my CATS::Problem $self, my $atts) = @_;

    my @t = @{$self->{current_tests}};

    for my $attr_name (qw/src param/)
    {
        defined(my $attr_value = $atts->{$attr_name}) or next;
        my $n = "do_In_$attr_name";
        $self->set_test_attr($_, $self->$n($_, $attr_value)) for @t;
    }
    if (defined $atts->{'use'})
    {
        my $gen_group = $atts->{genAll} ? ++$self->{gen_groups} : undef;
        for (@t)
        {
            my $use = apply_test_rank($atts->{'use'}, $_->{rank});
            $self->set_test_attr($_, 'generator_id',
                $self->get_imported_id($use) || $self->get_named_object($use)->{id});
            # TODO
            $self->set_test_attr($_, 'gen_group', $gen_group);
        }
        $self->note(
            "Generator group $gen_group created for tests " . join ',', map $_->{rank}, @t) if $gen_group;
    }
}


sub start_tag_Out
{
    (my CATS::Problem $self, my $atts) = @_;

    my @t = @{$self->{current_tests}};

    if (defined $atts->{src})
    {
        for (@t)
        {
            my $src = apply_test_rank($atts->{'src'}, $_->{rank});
            my $member = $self->{zip}->memberNamed($src)
                or $self->error("Invalid test output file reference: '$src'");
            $self->set_test_attr($_, 'out_file', $self->read_member($member, $self->{debug}));
        }
    }
    if (defined $atts->{'use'})
    {
        for (@t)
        {
            my $use = apply_test_rank($atts->{'use'}, $_->{rank});
            $self->set_test_attr($_, 'std_solution_id', $self->get_named_object($use)->{id});
        }
    }
}

sub apply_test_defaults
{
    (my CATS::Problem $self) = @_;
    my $d = $self->{test_defaults};
    # TODO: Вынести apply_test_rank
    for my $attr (qw(generator_id param std_solution_id points gen_group))
    {
        $d->{$attr} or next;
        $_->{$attr} ||= $d->{$attr} for values %{$self->{tests}};
    }
}

1;
