package Text::TeX;

#use strict;
#use vars qw($VERSION @ISA @EXPORT);

#require Exporter;
#require # AutoLoader;	# To quiet AutoSplit.

# @ISA = qw
# (Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public infunctions/methods/constants.
@EXPORT = qw(
	
);
$VERSION = '0.01';


# Preloaded methods go here.

# Does not deal with verbatims
# Spaces are treated bad.

$notusualtoks = "\\\\" . '\${}^_~&@%'; # Why \\\\? double interpretation!
$notusualtokenclass = "[$notusualtoks]";
$usualtokenclass = "[^$notusualtoks]";
$macro = '\\\\(?:[^a-zA-Z]|([a-zA-Z]+)\s*)'; # Contains one level of grouping
$active = "$macro|\\\$\\\$|\\^\\^.|$notusualtokenclass"; # 1 level of grouping
$tokenpattern = "($usualtokenclass)|$active"; # Two levels of grouping
$multitokenpattern = "($usualtokenclass+)|$active"; # Two levels of grouping
$commentpattern = "(?:%.*\n\s*)+";
$whitespaceAndComment = "\s*(%.*\n[ \t]*)+";
$optionalArgument = "(?:\\[([^]]*)\\])?"; # Contains one level of grouping

for (qw(Text::TeX::ArgToken Text::TeX::BegArgsToken Text::TeX::EndArgsToken )) {
 $pseudo{$_} = 1;
}


{
 package Text::TeX::Comment;
 $ignore = 1;
}

{
 package Text::TeX::Token;
 @ISA = ('Text::TeX::Chunk');

 sub refine {
 my $self = shift;
 return undef unless defined $self->[0];
 my $txt = shift;
 my $type;
 if (defined ($tok = $txt->{tokens}->{$self->[0]}) 
	and defined $tok->{class}) {
 bless $self, $tok->{class};
}
}
}

@Text::TeX::Text::ISA = ('Text::TeX::Chunk');
@Text::TeX::ArgToken::ISA = ('Text::TeX::Chunk');
@Text::TeX::BegArgsToken::ISA = ('Text::TeX::Chunk');
@Text::TeX::BegArgsTokenLookedAhead::ISA = ('Text::TeX::BegArgsToken');
@Text::TeX::EndArgsToken::ISA = ('Text::TeX::Chunk');
@Text::TeX::LookAhead::ISA = ('Text::TeX::EndArgsToken');
@Text::TeX::Paragraph::ISA = ('Text::TeX::Chunk');
@Text::TeX::End::Group::Args::ISA = ('Text::TeX::End::Group');
@Text::TeX::Begin::Group::Args::ISA = ('Text::TeX::Begin::Group');
@Text::TeX::EndLocal::ISA = ('Text::TeX::Chunk');
@Text::TeX::Separator::ISA = ('Text::TeX::Chunk');

{
 package Text::TeX::Chunk;
 sub refine {}
 sub digest {}
 sub collect {$_[0]->[0]}
 sub new {
 my $class = shift;
 bless [@_], $class;
}
 sub print {$_[0]->[0]}
}

{
 package Text::TeX::Group;
 sub new {shift; my $in = shift; bless $in}
 sub print {
 local @arr;
 foreach (@{$_[0]}) {
 push(@arr, $_->print);
}
 "`" . join("',`", @arr) . "'";
}
}

{
 package Text::TeX::End::Group;
 @ISA = ('Text::TeX::Chunk');
 sub new {shift; my $in = shift; bless \$in}
 sub digest {			# 0: the token, 1: text object
 return if $_[1]->check_presynthetic($_[0]);	# May change $_[0]
 my $wa = $_[1]->curwaitforaction;
 my $w = $_[1]->popwait;
 warn "Expecting `$w', got `$_[0][0]'=`$_[0][0][0]' in `$ {$_[1]->{paragraph}}'" 
 if $w ne $_[0]->[0];
 &$wa if defined $wa;
}
}

{
 package Text::TeX::End::Group::Args;
 sub digest {			# 0: the token, 1: text object
 my $Token = $_[1]->{tokens}->{$_[0]->[0]};
 my $count = $Token->{eatargs};
 my ($tok, @arr);
 while ($count--) {
 $tok = $_[1]->eatGroup(1);
 if (@$tok == 3 and $tok->[0]->[0] eq '{') {# Special case for {\a}
	$tok = $tok->[1];
}
 push(@arr,$tok);
}
 #$_[0]->[0] .= ' ' . join ' ', map $_->[0], @arr;
 $_[0]->[3] = \@arr;
 my $s = $_[1]->starttoken;
 my $wa = $_[1]->curwaitforaction;
 my $w = $_[1]->popwait;
 warn "Expecting `$w', got $_[0]->[0] in `$ {$_[1]->{paragraph}}'" 
 if $w ne $_[0]->[0];
 if ($Token->{selfmatch} and $s->[3]->[0]->[0] ne $_[0]->[3]->[0]->[0]) {
 warn "Expecting `$w" . "{$s->[3]->[0]->[0]}', got $_[0]->[0]" 
	. "{$_[0]->[3]->[0]->[0]} in `$ {$_[1]->{paragraph}}'";
}
 &$wa if defined $wa;
 $_[0]->[4] = $s;		# Put the start data into the token
}
}

{
 package Text::TeX::Begin::Group::Args;
 sub digest {			# 0: the token, 1: text object
 my $Token = $_[1]->{tokens}->{$_[0]->[0]};
 my $count = $Token->{eatargs};
 my ($tok, @arr);
 while ($count--) {
 $tok = $_[1]->eatGroup(1);
 if (@$tok == 3 and $tok->[0]->[0] eq '{') {# Special case for {\a}
	$tok = $tok->[1];
}
 push(@arr,$tok);
}
 # $_[0]->[0] .= ' ' . join ' ', map $_->[0], @arr;
 $_[0]->[3] = \@arr;
 $_[0]->SUPER::digest($_[1]);
}
}

{
 package Text::TeX::Begin::Group;
 @ISA = ('Text::TeX::Chunk');
 # 0: the token, 1: text object
 sub digest {$_[1]->pushwait($_[0])}
}

{
 package Text::TeX::SelfMatch;
 @ISA = ('Text::TeX::Chunk');
 sub refine {
 if ($_[1]->curwait eq $_[0]->[0]) {
 bless $_[0], Text::TeX::End::Group;
} else {
 bless $_[0], Text::TeX::Begin::Group;
}
}
 # 0: the token, 1: text object
 sub digest {			# XXXX Should not be needed?
 if ($_[1]->curwait eq $_[0]->[0]) {
 bless $_[0], Text::TeX::End::Group;
 $_[0]->Text::TeX::End::Group::digest($_[1]);
} else {
 bless $_[0], Text::TeX::Begin::Group;
 $_[1]->pushwait($_[0]);
}
}
}

{
 package Text::TeX::GetParagraph;
 sub new {
 shift; 
 my $file = shift;
 my $fh;
 $fh = $ {$file->{fhs}}[-1] if @{$file->{fhs}};
 return undef if (not defined $fh or eof($fh)) and $file->{readahead} eq "";
 my $string = $file->{readahead};
 if (defined $fh) {
 while (($in = <$fh>) =~ /\S/) {
	$string .= $in;
}
 while ( (($in = <$fh>) !~ /\S/) && !eof($fh)) {
	$string .= $in;
}
 $file->{readahead} = $in;
} else {
 $file->{readahead} = '';
}
 bless \$string;
}
}


{
 package Text::TeX::OpenFile;

 $refgen = "TeXOpenFile0000";

 sub new {
 shift; my $file = shift; my %opt = @_;
 if (defined $file) {
 ++$refgen;
 open("::$refgen",$file) || die "Cannot open $file: $!";
 die "End of file `$file' during opening" if eof("::$refgen");
}
 my $fhs = defined $file ? ["::$refgen"] : [];
 bless {fhs => $fhs, 
	 readahead => ($opt{string} || ""), 
	 files => [$file],
	 "paragraph" => undef, 
	 "tokens" => ($opt{tokens} || \%Text::TeX::Tokens),
	 waitfors => [], options => \%opt,
	 waitforactions => [],
	 defaultacts => [$opt{defaultact}],	# The last element is
 # the default action
 # for next deeper
 # level
	 actions => [defined $opt{action} ? 
			 $opt{action} : 
			 $opt{defaultact}],
	 waitargcounts => [0],
	 pending_out => [],	# Pseudotokens for output
	 pending_in => [],	# Pseudotokens for input
	 synthetic => [[]],	# Pseudotokens to deliver after block ends
	 presynthetic => [[]], # Pseudotokens to deliver before block ends
	};
}
 sub DESTROY {
 my $in = shift; my $i = 0;
 for (@{$in->{fhs}}) {
 close($_)
	|| die "Cannot close $ {$in->{files}}[$i]: $!";
 $i++;
}
}

 sub paragraph {
 my $in = shift;
 #print "ep.in=$in\n";
 if ($in->{"paragraph"} and $ {$in->{"paragraph"}} ne "") {
 $in->{"paragraph"};
} elsif (@{$in->{fhs}} and eof($ {$in->{fhs}}[-1])) {
 undef;
} elsif (!@{$in->{fhs}} and $in->{readahead} eq '') {
 undef;
} else {
 #warn "getting new\n";
 $in->{"paragraph"} = new Text::TeX::GetParagraph $in;
 return "";
}
}

 sub pushwait {		# 0: text object, 1: token, 2: ????
 push(@{$_[0]->{starttoken}}, $_[1]);
 push(@{$_[0]->{waitfors}}, $_[0]->{tokens}{$_[1]->[0]}{waitfor});
 push(@{$_[0]->{actions}}, 
	 defined $_[2] ? $_[2] : $_[0]->{defaultacts}[-1]);
 push(@{$_[0]->{waitforactions}}, $_[3]);
 push(@{$_[0]->{synthetic}}, []);
 push(@{$_[0]->{presynthetic}}, []);
}

 sub popwait {
 if ($#{$_[0]->{waitfors}} < 0) {
 warn "Got negative depth"; return;
}
 my $rest = pop(@{$_[0]->{synthetic}});
 warn "Not enough arguments" if @$rest;
 $rest = pop(@{$_[0]->{presynthetic}});
 warn "Presyntetic events remaining" if @$rest;
 pop(@{$_[0]->{starttoken}});
 pop(@{$_[0]->{actions}});
 pop(@{$_[0]->{waitforactions}});
 pop(@{$_[0]->{waitfors}});
}

 sub popsynthetic {
 my $rest = $ {$_[0]->{synthetic}}[-1];
 if (@$rest) {
 push @{$_[0]->{pending_out}}, reverse @{pop @$rest};
} 
}

 sub pushsynthetic {		# Add new list of events to do after the
 # next end of group.
 my $rest = $ {shift->{synthetic}}[-1];
 push @$rest, [@_];
}

 sub addpresynthetic {		# Add to the list of events to do before
 # the next end of group $uplevel above.
 my ($txt) = (shift);
 my $rest = $ {$txt->{presynthetic}}[-1];
 push @$rest, @_;
# if (@$rest) {
# push @{@$rest->[-1]}, @_;
#} else {
# push @$rest, [@_];
#}
}

 sub check_presynthetic {	# 0: text, 1: end token. Returns true on success
 if (@{$_[0]->{presynthetic}[-1]}) {
 my $rest = $_[0]->{presynthetic}[-1];
 my $next = pop @$rest;
 push @{$_[0]->{pending_in}}, $_[1], (reverse @$rest);
 $#$rest = -1;		# Delete them
 $_[1] = $next;
 return 1;
}
}
 

 sub curwait {
 my $ref = $_[0]->{waitfors}; $$ref[-1];
}

 sub curwaitforaction {
 my $ref = $_[0]->{waitforactions}; $$ref[-1];
}

 sub starttoken {
 my $ref = $_[0]->{starttoken}; $$ref[-1];
}

 # These are default bindings. You probably should override it.

 sub eatOptionalArgument {
 my $in = shift->paragraph;
 return undef unless defined $in;
 my $comment = ( $$in =~ s/^\s*($Text::TeX::commentpattern)//o );
 if ($$in =~ s/^\s*$Text::TeX::optionalArgument//o) {
 new Text::TeX::Token $1, $comment;
} else {
 warn "No optional argument found";
 if ($comment) {new Text::TeX::Token undef, $comment}
 else {undef}
} 
}

 sub eatFixedString {
 my $in = shift->paragraph;
 return undef unless defined $in;
 my $str = shift;
 my ($comment) = ( $$in =~ s/^\s*($Text::TeX::commentpattern)//o );
 if ($$in =~ s/^\s*$str//) {new Text::TeX::Token $&, $comment}
 else {
 warn "String `$str' expected, not found";
 if ($comment) {new Text::TeX::Token undef, $comment}
 else {undef}
} 
}

 sub eatBalanced {
 my $txt = shift;
 my ($in);
 warn "Did not get `{' when expected", return undef
 unless defined ($in = $txt->eatFixedString('{')) && defined ($in->[0]);
 $txt->eatBalancedRest;
}

 sub eatBalancedRest {
 my $txt = shift;
 my ($count,$in,@in) = (1);
 EAT:
 {
 warn "Unfinished balanced next", last EAT 
	unless defined ($in = $txt->eatMultiToken) && defined $in->[0];
 push(@in,$in);
 $count++,next if $in->[0] eq '{';
 $count-- if $in->[0] eq '}';
 pop(@in), last EAT unless $count;
 redo EAT;
}
 bless \@in, 'Text::TeX::Group';
}

 sub eatGroup {		# If arg2==1 will eat exactly one
 # group, otherwise a group or a
 # multitoken.
 my $txt = shift;
 local ($in,$r,@in);
 if (defined ($in[0] = $txt->eatMultiToken(shift)) and defined $in[0]->[0]) {
 $in[0]->refine($txt);
 if (ref $in[0] ne 'Text::TeX::Begin::Group') {
	return $in[0];
} else {
	while (defined ($r=ref($in = $txt->eatGroup)) # Eat many groups
	 && $r ne 'Text::TeX::End::Group') {
	 push(@in,$in);
	}
	if (defined $r) {push(@in,$in)}
	else {warn "Uncompleted group"}
}
} else {
 warn "Got nothing when argument expected";
 return undef;
}
 bless \@in, 'Text::TeX::Group';
}

 sub eatUntil {		# We suppose that the text to match
				# fits in a paragraph 
 my $txt = shift;
 my $m = shift;
 my ($in,@in);
 while ( (!defined $txt->{'paragraph'} || $ {$txt->{'paragraph'}} !~ /$m/)
	 && defined ($in = $txt->eatGroup(1))) {
 push(@in,@$in);
}
 ($ {$txt->{'paragraph'}} =~ s/$m//) || warn "Delimiter `$m' not found";
 bless \@in, 'Text::TeX::Group';
}

 sub lookAheadToken {		# If arg2, will eat one token
 my $txt = shift;
 my $in = $txt->paragraph;
 return '' unless $in;	# To be able to match without warnings
 my $comment = undef;
 if ($$in =~ 
	/^(?:\s*)(?:$Text::TeX::commentpattern)?($Text::TeX::tokenpattern)/o) {
 if (defined $2) {return $1}
 elsif (defined $3) {return "\\$3"} # Multiletter
 elsif (defined $1) {return $1}
}
 return '';
}
 
 sub eatMultiToken {		# If arg2, will eat one token
 my $txt = shift;
 my $in = $txt->paragraph;
 return undef unless defined $in;
 return new Text::TeX::Paragraph unless $in;
 my $comment = undef;
 $comment = $2 if $$in =~ s/^(\s*)($Text::TeX::commentpattern)/$1/o;
 my $nomulti = shift;
 # Cannot use if () BLOCK, because $& is local.
 $got = $$in =~ s/^\s*($Text::TeX::tokenpattern)//o	if $nomulti;
 $got = $$in =~ s/^\s*($Text::TeX::multitokenpattern)//o	unless $nomulti;
 if ($got and defined $2) {new Text::TeX::Text $&, $comment}
 elsif ($got and defined $3) {new Text::TeX::Token "\\$3", $comment} # Multiletter
 elsif ($got and defined $1) {new Text::TeX::Token $1, $comment}
 elsif ($comment) {new Text::TeX::Token undef, $comment}
 else {undef}
}

 sub eat {
 my $txt = shift;
 if ( @{$txt->{pending_out}} ) {
 my $out = pop @{$txt->{pending_out}};
 if (ref $out eq 'Text::TeX::LookAhead') {
	my $in = $txt->lookAheadToken;
	#my $in = $txt->eatMultiToken(1);
	#push @{$txt->{pending_in}}, $in;
	#$in = $in->[0];
	if (defined ($res = $out->[0][2]{$in})) {
	 push @{$out->[0]}, $in, $res;
	 $in = $txt->eatMultiToken(1);	# XXXX may be wrong if next
 # token needs to be eaten in
 # the style `multi', like \left.
	 splice @{$txt->{pending_in}}, 
	 0, 0, (bless \$in, 'Text::TeX::LookedAhead');
	 return $out;
	} else {
	 return bless $out, 'Text::TeX::EndArgsToken';
	}
} else {
	return $out;
}
}
 my $in = pop @{$txt->{pending_in}};
 my $after_lookahead;
 if (defined $in) {
 $in = $$in, $after_lookahead = 1 
	if ref $in eq 'Text::TeX::LookedAhead';
} else {
 my $one;
 $one = 1 if @{$txt->{synthetic}[-1]}; # Need to eat a group.
 $in = $txt->eatMultiToken($one);
}
 return undef unless defined $in;
 $in->refine($txt);
 $in->digest($txt);
 $txt->popsynthetic;		# Bad timing? XXXX
 my ($Token, $type, @arr);
 return $in 
 unless defined $in && defined $in->[0] 
	&& $in->[0] =~ /$Text::TeX::active/o
	&& defined ( $Token = $txt->{tokens}->{$in->[0]} );
 $type = $Token->{Type} or return $in;
 my $out = $in;
 if ($type eq 'action') {
 return &{$Token->{sub}}($in);
} elsif ($type eq 'argmask') {
 # eatWithMask;		# ????
} elsif ($type eq 'args') {
 # Args eaten already
} elsif ($type eq 'local') {
 $txt->addpresynthetic(new Text::TeX::EndLocal $in);
} elsif ($type eq 'report_args') {
 my $count = $Token->{count};
 my $ordinal = $count;
 my $res;
 if ($res = $Token->{lookahead}) {
	$txt->pushsynthetic(new Text::TeX::LookAhead [$in, $count, $res]);
} else {
	$txt->pushsynthetic(new Text::TeX::EndArgsToken [$in, $count]);	
}
 while (--$ordinal) {
	$txt->pushsynthetic(new Text::TeX::ArgToken [$in, $count, $ordinal]);
}
 if ($after_lookahead) {
	$out = new Text::TeX::BegArgsTokenLookedAhead [$in, $count];
} else {
	$out = new Text::TeX::BegArgsToken [$in, $count];
}
} else {
 warn "Format of token data unknown for `", $in->[0], "'"; 
}
 return $out;
}
 
 sub report_arg {
 my $n = shift;
 my $max = shift;
 my $act = shift;
 my $lastact = shift;
 if ($n == $max) {
 &$lastact($n);
} else {
 &$act($n,$max);
}
}

 sub eatDefine {
 my $txt = shift;
 my ($args, $body);
 warn "No `{' found after defin", return undef 
 unless $args = $txt->eatUntil('{');
 warn "Argument list @$args too complicated", return undef 
 unless @$args == 1 && $$args[0] =~ /^(\ \#\d)*$/;
 warn "No `}' found after defin", return undef 
 unless $body = $txt->eatBalancedRest;
 #my @args=split(/(\#[\d\#])/,$$); # lipa
}
 
 sub process {
 my ($txt, $eaten, $act) = (shift);
 while (defined ($eaten = $txt->eat)) {
 if (defined ($act = $txt->{actions}[-1])) {
	&$act($eaten,$txt);
}
}
}
}

%super_sub_lookahead = qw( ^ 1 _ 0 \\sb 0 \\sp 1 \\Sp 1 \\Sb 0 );

# class => 'where to bless to', Type => how to process
# eatargs => how many args to swallow before digesting

%Tokens = (
 '{' => {'class' => 'Text::TeX::Begin::Group', 'waitfor' => '}'},
 '}' => {'class' => 'Text::TeX::End::Group'},
 "\$" => {'class' => 'Text::TeX::SelfMatch', waitfor => "\$"},
 '$$' => {'class' => 'Text::TeX::SelfMatch', waitfor => '$$'},
 '\begin' => {class => 'Text::TeX::Begin::Group::Args', 
	 eatargs => 1, 'waitfor' => '\end', selfmatch => 1},
 '\end' => {class => 'Text::TeX::End::Group::Args', eatargs => 1, selfmatch => 1},
 '\left' => {class => 'Text::TeX::Begin::Group::Args', 
	 eatargs => 1, 'waitfor' => '\right'},
 '\right' => {class => 'Text::TeX::End::Group::Args', eatargs => 1},
 '\frac' => {Type => 'report_args', count => 2},
 '\sqrt' => {Type => 'report_args', count => 1},
 '\text' => {Type => 'report_args', count => 1},
 '\operatorname' => {Type => 'report_args', count => 1},
 '\operatornamewithlimits' => {Type => 'report_args', count => 1},
 '^' => {Type => 'report_args', count => 1, 
	 lookahead => \%super_sub_lookahead},
 '_' => {Type => 'report_args', count => 1, 
	 lookahead => \%super_sub_lookahead},
 '\em' => {Type => 'local'},
 '\bold' => {Type => 'local'},
 '\it' => {Type => 'local'},
 '\rm' => {Type => 'local'},
 '\mathcal' => {Type => 'local'},
 '\mathfrak' => {Type => 'local'},
 '\mathbb' => {Type => 'local'},
 '\\\\' => {'class' => 'Text::TeX::Separator'},
 '&' => {'class' => 'Text::TeX::Separator'},
);

{
 my $i = 0;
 @symbol = (
 (undef) x 8,		# 1st row
 (undef) x 8,
 (undef) x 8,		# 2nd row
 (undef) x 8,
 undef, undef, '\forall', undef, '\exists', undef, undef, '\???', # 3rd: symbols
 (undef) x 8,
 (undef) x 8, # 4th: numbers and symbols
 (undef) x 8,
 '\???', ( map {"\\$_"} 
		 qw(Alpha Beta Chi Delta Epsilon Phi Gamma 
		 Eta Iota vartheta Kappa Lambda Mu Nu Omicron 
		 Pi Theta Rho Sigma Tau Ypsilon varsigma Omega
		 Xi Psi Zeta)), undef, '\therefore', undef, '\perp', undef,
 undef, ( map {"\\$_"} 
	 qw(alpha beta chi delta varepsilon phi gamma
		 eta iota varphi kappa lambda mu nu omicron
		 pi theta rho sigma tau ypsilon varpi omega
		 xi psi zeta)), undef, undef, undef, undef, undef,
 (undef) x 8,		# 9st row
 (undef) x 8,
 (undef) x 8,		# 10nd row
 (undef) x 8,
 undef, undef, undef, '\leq', undef, '\infty', undef, undef, # 11th row
 undef, undef, undef, undef, '\from', undef, '\to', undef,
 '\circ', '\pm', undef, '\geq', '\times', undef, '\partial', '\bullet', # 12th row
 undef, '\neq', '\equiv', '\approx', '\dots', '\mid', '\hline', undef,
 '\Aleph', undef, undef, undef, '\otimes', '\oplus', '\empty', '\cap', # 13th row
 '\cup', undef, undef, undef, undef, undef, '\in', '\notin',
 undef, '\nabla', undef, undef, undef, '\prod', undef, '\cdot', # 14th row
 undef, '\wedge', '\vee', undef, undef, undef, undef, undef,
 undef, '\<', undef, undef, undef, '\sum', undef, undef, # 15th row
 (undef) x 8,
 undef, '\>', '\int', (undef) x 5, # 16th row
 (undef) x 8,
 );
 for (@symbol) {
 $xfont{$_} = ['symbol', chr($i)] if defined $_;
 $i++;
}
}

# This list was autogenerated by the following script:
# Some handediting is required since MSSYMB.TEX is obsolete.

## Usage is like:
##		extract_texchar.pl PLAIN.TEX MSSYMB.TEX
##$family = shift;

#%fonts = (2 => "cmsy", 3 => "cmex", '\\msx@' => msam, '\\msy@' => msbm, );

#while (defined ($_ = <ARGV>)) {
# $list{$fonts{$2}}[hex $3] = $1
# if /^\s*\\mathchardef(\\\w+)=\"\d([23]|\\ms[xy]\@)([\da-fA-F]+)\s+/o;
#}

#for $font (keys %list) {
# print "\@$font = (\n ";
# for $i (0 .. $#{$list{$font}}/8) {
# print join ', ', map {packit($_)} @{$list{$font}}[ 8*$i .. 8*$i+7 ];
# print ",\n ";
#}
# print ");\n\n";
#}

#sub packit {
# my $cs = shift;
# if (defined $cs) {
# #$cs =~ s/\\\\/\\\\\\\\/g;
# "'$cs'";
#} else {
# 'undef';
#}
#}

@cmsy = (
 undef, '\cdotp', '\times', '\ast', '\div', '\diamond', '\pm', '\mp',
 '\oplus', '\ominus', '\otimes', '\oslash', '\odot', '\bigcirc', '\circ', '\bullet',
 '\asymp', '\equiv', '\subseteq', '\supseteq', '\leq', '\geq', '\preceq', '\succeq',
 '\sim', '\approx', '\subset', '\supset', '\ll', '\gg', '\prec', '\succ',
 '\leftarrow', '\rightarrow', '\uparrow', '\downarrow', '\leftrightarrow', '\nearrow', '\searrow', '\simeq',
 '\Leftarrow', '\Rightarrow', '\Uparrow', '\Downarrow', '\Leftrightarrow', '\nwarrow', '\swarrow', '\propto',
 '\prime', '\infty', '\in', '\ni', '\bigtriangleup', '\bigtriangledown', '\not', '\mapstochar',
 '\forall', '\exists', '\neg', '\emptyset', '\Re', '\Im', '\top', '\perp',
 '\aleph', undef, undef, undef, undef, undef, undef, undef,
 undef, undef, undef, undef, undef, undef, undef, undef,
 undef, undef, undef, undef, undef, undef, undef, undef,
 undef, undef, undef, '\cup', '\cap', '\uplus', '\wedge', '\vee',
 '\vdash', '\dashv', undef, undef, undef, undef, undef, undef,
 '\langle', '\rangle', '\mid', '\parallel', undef, undef, '\setminus', '\wr',
 undef, '\amalg', '\nabla', '\smallint', '\sqcup', '\sqcap', '\sqsubseteq', '\sqsupseteq',
 undef, '\dagger', '\ddagger', undef, '\clubsuit', '\diamondsuit', '\heartsuit', '\spadesuit',
 );

@cmex = (
 undef, undef, undef, undef, undef, undef, undef, undef, # 0-7
 undef, undef, undef, undef, undef, undef, undef, undef, # 8-15
 undef, undef, undef, undef, undef, undef, undef, undef, # 16-23
 undef, undef, undef, undef, undef, undef, undef, undef, # 24-31
 undef, undef, undef, undef, undef, undef, undef, undef, # 32-39
 undef, undef, undef, undef, undef, undef, undef, undef, # 40-47
 undef, undef, undef, undef, undef, undef, undef, undef, # 48-55
 undef, undef, undef, undef, undef, undef, undef, undef, # 56-64
 undef, undef, undef, undef, undef, undef, '\bigsqcup', undef,	# 64-71
 '\ointop', undef, '\bigodot', undef, '\bigoplus', undef, '\bigotimes', undef,	# 72-79
 '\sum', '\prod', '\intop', '\bigcup', '\bigcap', '\biguplus', '\bigwedge', '\bigvee',	# 80-87
 undef, undef, undef, undef, undef, undef, undef, undef,
 '\coprod', undef, undef, undef, undef, undef, undef, undef,
 );

@msam = (
 '\boxdot', '\boxplus', '\boxtimes', '\square', '\blacksquare', '\centerdot', '\lozenge', '\blacklozenge',
 '\circlearrowright', '\circlearrowleft', '\rightleftharpoons', '\leftrightharpoons', '\boxminus', '\Vdash', '\Vvdash', '\vDash',
 '\twoheadrightarrow', '\twoheadleftarrow', '\leftleftarrows', '\rightrightarrows', '\upuparrows', '\downdownarrows', '\upharpoonright', '\downharpoonright',
 '\upharpoonleft', '\downharpoonleft', '\rightarrowtail', '\leftarrowtail', '\leftrightarrows', '\rightleftarrows', '\Lsh', '\Rsh',
 '\rightsquigarrow', '\leftrightsquigarrow', '\looparrowleft', '\looparrowright', '\circeq', '\succsim', '\gtrsim', '\gtrapprox',
 '\multimap', '\therefore', '\because', '\doteqdot', '\triangleq', '\precsim', '\lesssim', '\lessapprox',
 '\eqslantless', '\eqslantgtr', '\curlyeqprec', '\curlyeqsucc', '\preccurlyeq', '\leqq', '\leqslant', '\lessgtr',
 '\backprime', undef, '\risingdotseq', '\fallingdotseq', '\succcurlyeq', '\geqq', '\geqslant', '\gtrless',
 '\sqsubset', '\sqsupset', '\vartriangleright', '\vartriangleleft', '\trianglerighteq', '\trianglelefteq', '\bigstar', '\between',
 '\blacktriangledown', '\blacktriangleright', '\blacktriangleleft', undef, undef, '\vartriangle', '\blacktriangle', '\triangledown',
 '\eqcirc', '\lesseqgtr', '\gtreqless', '\lesseqqgtr', '\gtreqqless', '\yen', '\Rrightarrow', '\Lleftarrow',
 '\checkmark', '\veebar', '\barwedge', '\doublebarwedge', '\angle', '\measuredangle', '\sphericalangle', '\varpropto',
 '\smallsmile', '\smallfrown', '\Subset', '\Supset', '\Cup', '\Cap', '\curlywedge', '\curlyvee',
 '\leftthreetimes', '\rightthreetimes', '\subseteqq', '\supseteqq', '\bumpeq', '\Bumpeq', '\lll', '\ggg',
 '\ulcorner', '\urcorner', '\circledR', '\circledS', '\pitchfork', '\dotplus', '\backsim', '\backsimeq',
 '\llcorner', '\lrcorner', '\maltese', '\complement', '\intercal', '\circledcirc', '\circledast', '\circleddash',
 );

@msbm = (
 '\lvertneqq', '\gvertneqq', '\nleq', '\ngeq', '\nless', '\ngtr', '\nprec', '\nsucc',
 '\lneqq', '\gneqq', '\nleqslant', '\ngeqslant', '\lneq', '\gneq', '\npreceq', '\nsucceq',
 '\precnsim', '\succnsim', '\lnsim', '\gnsim', '\nleqq', '\ngeqq', '\precneqq', '\succneqq',
 '\precnapprox', '\succnapprox', '\lnapprox', '\gnapprox', '\nsim', '\ncong', undef, undef,
 '\varsubsetneq', '\varsupsetneq', '\nsubseteqq', '\nsupseteqq', '\subsetneqq', '\supsetneqq', '\varsubsetneqq', '\varsupsetneqq',
 '\subsetneq', '\supsetneq', '\nsubseteq', '\nsupseteq', '\nparallel', '\nmid', '\nshortmid', '\nshortparallel',
 '\nvdash', '\nVdash', '\nvDash', '\nVDash', '\ntrianglerighteq', '\ntrianglelefteq', '\ntriangleleft', '\ntriangleright',
 '\nleftarrow', '\nrightarrow', '\nLeftarrow', '\nRightarrow', '\nLeftrightarrow', '\nleftrightarrow', '\divideontimes', '\varnothing',
 '\nexists', undef, undef, undef, undef, undef, undef, undef,
 undef, undef, undef, undef, undef, undef, undef, undef,
 undef, undef, undef, undef, undef, undef, undef, undef,
 undef, undef, undef, undef, undef, undef, undef, undef,
 undef, undef, undef, undef, undef, undef, '\mho', '\eth',
 '\eqsim', '\beth', '\gimel', '\daleth', '\lessdot', '\gtrdot', '\ltimes', '\rtimes',
 '\shortmid', '\shortparallel', '\smallsetminus', '\thicksim', '\thickapprox', '\approxeq', '\succapprox', '\precapprox',
 '\curvearrowleft', '\curvearrowright', '\digamma', '\varkappa', undef, '\hslash', '\hbar', '\backepsilon',
 );

# Temporary workaround against Tk's \n (only cmsy contains often-used \otimes):

$cmsy[ord "\n"] = undef;

for $font (qw(cmsy cmex msam msbm)) {
 for $num (0 .. $#{$font}) {
 $xfont{$$font[$num]} = [$font, chr($num)] if defined $$font[$num];
}
}

%aliases = qw(
	 \int \intop \oint \ointop \restriction \upharpoonright
	 \Doteq \doteqdot \doublecup \Cup \doublecap \Cap
	 \llless \lll \gggtr \ggg \lnot \neg \land \wedge
	 \lor \vee \le \leq \ge \geq \owns \ni \gets \leftarrow
	 \to \rightarrow \< \langle \> \rangle \| \parallel
	 );

for $from (keys %aliases) {
 $xfont{$from} = $xfont{$aliases{$from}} if exists $xfont{$aliases{$from}};
}


# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__

=head1 NAME

Text::TeX -- Perl module for parsing of C<TeX>.

=head1 SYNOPSIS

 use Text::TeX;

 sub report {
 my($eaten,$txt) = (shift,shift);
 print "Comment: `", $eaten->[1], "'\n" if defined $eaten->[1];
 print "@{$txt->{waitfors}} ", ref $eaten, ": `", $eaten->[0], "'";
 if (defined $eaten->[3]) {
 my @arr = @{$eaten->[3]};
 foreach (@arr) {
	print " ", $_->print;
}
}
 print "\n";
}

 my $file = new Text::TeX::OpenFile 'test.tex',
 'defaultact' => \&report;
 $file->process;

=head1 DESCRIPTION

A new C<TeX> parser is created by

 $file = new Text::TeX::OpenFile $filename, attr1 => $val1, ...;

$filename may be C<undef>, in this case the text to parse may be
specified in the attribute C<string>.

Recognized attributes are:

=over 12

=item C<string>

contains the text to parse before parsing $filename.

=item C<defaultact>

denotes a procedure to submit C<output tokens> to.

=item C<tokens>

gives a hash of C<descriptors> for C<input token>. A sane default is
provided.

=back

A call to the method C<process> launches the parser.

=head2 Tokenizer

When the parser is running, it processes input stream by splitting it
into C<input tokens> using some I<heuristics> similar to the actual
rules of TeX tokenizer. However, since it does not use I<the exact
rules>, the resulting tokens may be wrong if some advanced TeX command
are used, say, the character classes are changed.

This should not be of any concern if the stream in question is a
"user" file, but is important for "packages".

=head2 Digester

The processed C<input tokens> are handled to the digester, which
handles them according to the provided C<tokens> attribute.

=head2 C<tokens> attribute

This is a hash reference which describes how the C<input tokens>
should be handled. A key to this hash is a literal like C<^> or
C<\fraction>. A value should be another hash reference, with the
following keys recognized:

=over 7

=item class

Into which class to bless the token. Several predefined classes are
provided. The default is C<Text::TeX::Token>.

=item Type

What kind of special processing to do with the input after the
C<class> methods are called. Recognized C<Type>s are:

=over 10

=item report_args

When the token of this C<Type> is encountered, it is converted into
C<Text::Tex::BegArgsToken>. Then the arguments are processed as usual,
and an C<output token> of type C<Text::Tex::ArgToken> is inserted
between them. Finally, after all the arguments are processed, an
C<output token> C<Text::Tex::EndArgsToken> is inserted.

The first element of these simulated C<output tokens> is an array
reference with the first element being the initial C<output token>
which generated this sequence. The second element of the internal
array is the number of arguments required by the C<input token>. The
C<Text::Tex::ArgToken> token has a third element, which is the ordinal
of the argument which ends immediately before this token.

If requested, a token C<Text::Tex::LookAhead> may be returned instead
of C<Text::Tex::EndArgsToken>. The additional elements of
C<$token->[0]> are: the reference to the corresponding C<lookahead>
attribute, the relevant key (text of following token) and the
corresponding value.

In such a case the input token which was looked-ahead would generate
an output token of type C<Text::Tex::BegArgsTokenLookedAhead> (if it
usually generates C<Text::Tex::BegArgsToken>).

=item local

Means that these macro introduces a local change, which should be
undone at the end of enclosing block. At the end of the block an
output event C<Text::TeX::EndLocal> is delivered, with C<$token->[0]>
being the output token for the I<local> event starting.

Useful for font switching. 

=back

=back

Some additional keys may be recognized by the code for the particular
C<class>.

=over 12

=item C<count>

number of arguments to the macro.

=item C<waitfor>

gives the matching token for a I<starting delimiter> token.

=item C<eatargs>

number of tokens to swallow literally and put into the relevant slot
of the C<output token>. The surrounding braces are stripped.

=item C<selfmatch>

is used with C<eatargs==1>. Denotes that the matching token is also
C<eatargs==1>, and the swallowed tokens should coinside (like with
C<\begin{blah} ... \end{blah}>).

=item C<lookahead>

is a hash with keys being texts of tokens which need to be treated
specially after the end of arguments for the current token. If the
corresponding text follows the token indeed, a token
C<Text::Tex::LookAhead> is returned instead of
C<Text::Tex::EndArgsToken>.

=back

=head2 Symbol font table

The hash %Text::TeX::xfont contains the translation table from TeX
tokens into the corresponding font elements. The values are array
references of the form C<[fontname, char]>, Currently the only font
supported is C<symbol>.

=cut

=head1 AUTHOR

Ilya Zakharevich, ilya@math.ohio-state.edu

=head1 SEE ALSO

perl(1).

=cut

