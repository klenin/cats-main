package TestLogger;

use strict;
use warnings;

sub new { bless { notes => [], warnings => [] }, $_[0]; }
sub note { push @{$_[0]->{notes}}, $_[1] }
sub warning { push @{$_[0]->{warnings}}, $_[1] }
sub error { die $_[1] }

1;
