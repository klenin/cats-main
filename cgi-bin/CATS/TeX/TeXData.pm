# MathRender v1.2 by Matviyenko Victor
# все символы, которые умеют отображать html и mathml генераторы
package CATS::TeX::TeXData;
# команда ТеХ без бэкслеша => html/mathml entity без &и;
# при добавлении новых символов могут возникнуть проблемы при отображении html
# (только в случае отсутствия у клиента обоих используемых генератором шрифтов)
our %binary =
(
 pm => '#xB1',
 mp => '#x2213',
 circ => '#x2218',
 bullet => 'bull',
 cap => 'cap',
 cup => 'cup',
 vee => 'and',
 wedge => 'or',
 oplus => 'oplus',
 ominus => '#x2296',
 otimes => 'otimes',
 odot => '#x2299',
 oslash => 'empty',
 bigcirc => '#x25CB',
 cdot => '#x22C5',
 'times' => 'times',
 'le' => 'le',
 'ge' => 'ge',
 'ne' => 'ne',
 'lt' => 'lt',
 'gt' => 'gt',
 ll => '#x226A',
 gg => '#x226B',
 approx => 'asymp',
 equiv => 'equiv',
 parallel =>'#x2225',
 perp => 'perp',
 in => 'isin',
 notin => 'notin',
 ni => 'ni',
 subset => 'sub',
 subseteq => 'sube',
 supset => 'sub',
 supseteq => 'supe',
 to => '#x21A6',
 lnot => 'not',
 lor => 'or',
 land => 'and',
 cdots => '#x22ef',
);

my %arrows =
(
 Rightarrow => 'rArr',
 Leftarrow => 'lArr',
 Leftrightarrow => 'hArr',
 Uparrow => 'uArr',
 Downarrow => 'dArr',
 leftarrow => 'larr',
 rightarrow => 'rarr',
 uparrow => 'uarr',
 downarrow => 'darr',
);

my %special =
(
 deg => 'deg',
 'int' => 'int',
 sum => 'sum',
 prod => 'prod',
 'sqrt' => '#x221A',
 partial => 'part',
 triangle => '#x25B3',
 angle => 'ang',
 infty => 'infin',
 forall => 'forall',
 'exists' => 'exist',
 emptyset => 'empty',
 neg => '#xAC',
 nabla => 'nabla',
 dots => 'hellip',
 ldots => 'hellip',
 goodbreak => 'zwnj',
 leftguilsingl => 'lsaquo',
 nobreak => 'zwj',
 quotedblbase => 'bdquo',
 quotesinglbase => 'sbquo',
 rightguilsingl => 'rsaquo',
 lceil => '#x2308',
 rceil => '#x2309',
 lfloor => '#x230A',
 rfloor => '#x230B',
);

my %spaces =
(
 #соответствие неточное
 ';' => 'nbsp',
 ':' => 'nbsp',
 ',' => 'nbsp',
);

my %greek =
(
 Alpha => 'Alpha',
 Beta => 'Beta',
 Chi => 'Chi',
 Delta => 'Delta',
 Epsilon => 'Epsilon',
 Eta => 'Eta',
 Gamma => 'Gamma',
 Iota => 'Iota',
 Kappa => 'Kappa',
 Lambda => 'Lambda',
 Mu => 'Mu',
 Nu => 'Nu',
 Omega => 'Omega',
 Omicron => 'Omicron',
 Phi => 'Phi',
 Pi => 'Pi',
 Psi => 'Psi',
 Rho => 'Rho',
 Sigma => 'Sigma',
 Tau => 'Tau',
 Theta => 'Theta',
 Upsilon => 'Upsilon',
 Xi => 'Xi',
 Zeta => 'Zeta',
 alpha => 'alpha',
 beta => 'beta',
 chi => 'chi',
 delta => 'delta',
 epsilon => 'epsilon',
 eta => 'eta',
 gamma => 'gamma',
 iota => 'iota',
 kappa => 'kappa',
 lambda => 'lambda',
 mu => 'mu',
 nu => 'nu',
 omega => 'omega',
 omicron => 'omicron',
 phi => 'phi',
 pi => 'pi',
 psi => 'psi',
 rho => 'rho',
 sigma => 'sigma',
 tau => 'tau',
 theta => 'theta',
 upsilon => 'upsilon',
 varsigma => 'sigmaf',
 xi => 'xi',
 zeta => 'zeta',
);

my %old =
(
 alef => '#x5D0',
 ayin => '#x5E2',
 bet => '#x5D1',
 dalet => '#x5D3',
 finalkaf => '#x5DA',
 finalmem => '#x5DD',
 finalnun => '#x5DF',
 finalpe => '#x5E3',
 finaltsadi => '#x5E5',
 gimel => '#x5D2',
 he => '#x5D4',
 het => '#x5D7',
 kaf => '#x5DB',
 lamed => '#x5DC',
 mem => '#x5DE',
 nun => '#x5E0',
 pe => '#x5E4',
 qof => '#x5E7',
 resh => '#x5E8',
 samekh => '#x5E1',
 shin => '#x5E9',
 tav => '#x5EA',
 tet => '#x5D8',
 tsadi => '#x5E6',
 vav => '#x5D5',
 yod => '#x5D9',
 zayin => '#x5D6',
);

# используемый генераторами хеш
our %symbols = (%binary, %arrows, %special, %spaces, %greek, %old);
%symbols = map { $_ => "\&$symbols{$_};" } keys %symbols;
$symbols{' '} = '&nbsp;';
$symbols{'-'} = '&minus;',
$symbols{'\}'} = '}';
$symbols{'\{'} = '{';
$symbols{'\backslash'} = "\\";

1;