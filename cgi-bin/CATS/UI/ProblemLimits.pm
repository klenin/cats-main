package CATS::UI::ProblemLimits;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB qw(:DEFAULT $db);
use CATS::Form;
use CATS::Globals qw($cid $contest $is_jury $is_root $t);
use CATS::ListView;
use CATS::Messages qw(msg res_str);
use CATS::Output qw(init_template url_f);
use CATS::Problem::Utils;
use CATS::StaticPages;

my $zero_undef = sub { $_[0] || undef };
my $fixed = CATS::Field::fixed(min => 0, max => 1e6, allow_empty => 1);
my @field_common = (editor => { size => 4 }, , before_save => $zero_undef);

our $form = CATS::Form->new(
    table => 'contest_problems CP',
    fields => [
        [ name => 'max_reqs', caption => 688, @field_common,
            validators => CATS::Field::int_range(min => 0, max => 1e6, allow_empty => 1) ],
        [ name => 'scaled_points', caption => 690, @field_common, validators => $fixed ],
        [ name => 'round_points_to', caption => 692, @field_common, validators => $fixed ],
        [ name => 'weight', caption => 691, @field_common, validators => $fixed ],
    ],
    href_action => '-', # Stub.
);

sub problem_limits_frame {
    my ($p) = @_;
    init_template($p, 'problem_limits.html.tt');
    $p->{pid} && $is_jury or return;

    my @fields = (@cats::limits_fields, 'job_split_strategy');
    my $original_limits_str = join ', ', 'NULL AS job_split_strategy', map "P.$_", @cats::limits_fields;
    my $overridden_limits_str = join ', ', map "L.$_ AS overridden_$_", @fields;
    my $form_fields_sql = $form->fields_sql;

    my $problem = $dbh->selectrow_hashref(qq~
        SELECT P.id, P.title, CP.id AS cpid, CP.tags, CP.limits_id,
        $form_fields_sql,
        $original_limits_str, $overridden_limits_str
        FROM problems P
        INNER JOIN contest_problems CP ON P.id = CP.problem_id
        LEFT JOIN limits L ON L.id = CP.limits_id
        WHERE P.id = ? AND CP.contest_id = ?~, undef,
        $p->{pid}, $cid) or return;
    CATS::Problem::Utils::round_time_limit($problem->{overridden_time_limit});

    $t->param(
        p => $problem,
        problem_title => $problem->{title},
        href_action => url_f('problem_limits', pid => $problem->{id}, cid => $cid,
            from_problems => $p->{from_problems})
    );

    CATS::Problem::Utils::problem_submenu('problem_limits', $p->{pid});

    my $fd = $form->parse_form_data($p);
    $t->param(fd => $fd);
    $fd->{indexed}->{max_reqs}->{caption} .= " ($contest->{max_reqs})" if $contest->{max_reqs};
    if (!$p->{override_contest}) {
        $fd->{indexed}->{$_}->{value} //= $problem->{$_} for keys %{$fd->{indexed}};
    }

    my $redirect_url = $p->{from_problems} && url_f('problems', limits_cpid => $problem->{cpid});

    if ($p->{override}) {
        my $new_limits = !defined $problem->{limits_id};

        my $limits = { map { $_ => $p->{$_} } grep $p->{$_}, @fields };
        my $filtered_limits = CATS::Request::filter_valid_limits($limits);

        return msg(1144) if !$new_limits && grep !exists $filtered_limits->{$_}, keys %$limits;

        $limits = {
            map { $_ => $limits->{$_} || $problem->{"overridden_$_"} || $problem->{$_} } @fields
        };

        $problem->{limits_id} = CATS::Request::set_limits($problem->{limits_id}, $limits);

        if ($new_limits) {
            $dbh->do(q~
                UPDATE contest_problems SET limits_id = ?
                WHERE id = ?~, undef,
            $problem->{limits_id}, $problem->{cpid});
        }

        for (@fields) {
            $problem->{"overridden_$_"} = $limits->{$_};
        }

        $dbh->commit;
        CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $problem->{cpid});

        msg($new_limits ? 1145 : 1146, $problem->{title});
        return $p->redirect($redirect_url) if $p->{from_problems} && !$new_limits;
    }
    elsif ($p->{clear_override}) {
        if ($problem->{limits_id}) {
            $dbh->do(q~
                UPDATE contest_problems SET limits_id = NULL
                WHERE id = ?~, undef,
            $problem->{cpid});
            CATS::Request::delete_limits($problem->{limits_id});
        }

        $dbh->commit;
        CATS::StaticPages::invalidate_problem_text(cid => $cid, cpid => $problem->{cpid});

        delete $problem->{limits_id};
        for (@fields) {
            delete $problem->{"overridden_$_"};
        }

        msg(1147, $problem->{title});
        return $p->redirect($redirect_url) if $p->{from_problems};
    }
    elsif ($p->{override_contest}) {
        return if grep $_->{error}, @{$fd->{ordered}};
        $form->save($problem->{cpid}, [ map $_->{value}, @{$fd->{ordered}} ], commit => 1);
        msg(1146, $problem->{title});
        return $p->redirect($redirect_url) if $p->{from_problems};
    }
}

1;
