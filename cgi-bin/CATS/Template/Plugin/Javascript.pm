package CATS::Template::Plugin::Javascript;

use Template::Plugin::Filter;
use base qw(Template::Plugin::Filter);

sub filter {
    my ($self, $text) = @_;
    $text =~ s/[\\'"]/\\$&/g;
    $text =~ s/[\n]/\\n/g;
    $text =~ s/[\b]/\\b/g;
    $text =~ s/[\f]/\\f/g;
    $text =~ s/[\r]/\\r/g;
    $text =~ s/[\t]/\\t/g;
    return $text;
}

1;