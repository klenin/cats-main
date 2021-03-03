use strict;
use warnings;

use Encode;
use File::Spec;
use FindBin;
use SQL::Abstract;
use Test::Exception;
use Test::More tests => 44;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib File::Spec->catdir($FindBin::Bin, '..', 'cats-problem');

use CATS::QueryBuilder;

my $sql = SQL::Abstract->new;
sub where { ($sql->where(@_))[0] }
sub qb_mask { CATS::QueryBuilder->new->parse_search($_[0])->get_mask }

is_deeply qb_mask('a=1'), { a => qr/^1$/i }, 'mask simple';
is_deeply qb_mask('a=2,  a=a'), { a => qr/^2$|^a$/i }, 'mask or';
is_deeply qb_mask('a=2 , b_c=dddd'), { a => qr/^2\ $/i, b_c => qr/^dddd$/i }, 'mask and';
is_deeply qb_mask('mm=*'), { mm => qr/^\*$/i }, 'mask quoting';
is_deeply qb_mask('not_eq!=a,starts^=b,contains~=c,not_contains!~d'),
    { not_eq => qr/^(?!a$).*$/i, starts => qr/^b/i, contains => qr/c/i, not_contains => qr/^(?!.*d)/i }, 'mask ops';
is_deeply qb_mask('zz?'), { zz => qr/./i }, 'mask not NULL';
is_deeply qb_mask('zz??'), { zz => qr/^$/i }, 'mask NULL';

{
    my $qb = CATS::QueryBuilder->new;
    $qb->default_searches([ 'a' ], nodb => 1);
    is_deeply $qb->parse_search('tt')->get_mask, { 'a' => qr/tt/i }, 'mask any default';
    is_deeply qb_mask('1,2'), { '' => qr/1|2/i }, 'mask any nodefault';
    is_deeply qb_mask('*=z'), { '' => qr/^z$/i }, 'mask any';
}

{
    my $mask = qb_mask('a!=b')->{a};
    unlike 'b', $mask, 'mask != 1';
    like 'bс', $mask, 'mask != 2';
    like 'c', $mask, 'mask != 3';
}
{
    my $mask = qb_mask('a!^b')->{a};
    unlike 'b', $mask, 'mask !^ 1';
    unlike 'bс', $mask, 'mask !^ 2';
    like 'cb', $mask, 'mask !^ 3';
}
{
    my $mask = qb_mask('a>3')->{a};
    unlike 2, $mask, 'mask gt 1';
    like 5, $mask, 'mask gt 2';
}
{
    my $mask = qb_mask('a>3.5')->{a};
    unlike 3, $mask, 'pt mask gt 3';
    like 4, $mask, 'pt mask gt 4';
}
{
    my $qb = CATS::QueryBuilder->new;
    $qb->define_db_searches([ 'a', 't.id' ]);
    $qb->define_db_searches({ sq => '(SELECT id FROM table)' });
    throws_ok { $qb->define_db_searches([ 'a' ]) } qr/duplicate/i, 'duplicate db_search';
    $qb->default_searches([ 'a' ]);
    throws_ok { $qb->default_searches([ 'z' ]) } qr/unknown/i, 'unknown default_search';

    $qb->define_enums({ a => { x => 22, y => 33 } });
    throws_ok { $qb->define_enums({ a => {} }) } qr/duplicate/i, 'duplicate enum';

    my $sq = 'EXISTS (SELECT * FROM table WHERE id = ?)';
    $qb->define_subqueries({ has_v => { sq => $sq } });
    throws_ok { $qb->define_subqueries({ has_v => {} }) } qr/duplicate/i, 'duplicate subquery';

    $qb->parse_search('a=1');
    is where($qb->make_where), " WHERE ( a = ? )", 'db simple sql';

    $qb->parse_search('a!=1,id=2,b=3');
    is_deeply $qb->get_mask, { b => qr/^3$/i }, 'mask db';
    is_deeply $qb->make_where, { a => [ { '!=', 1 } ], 't.id' => [ { '=', 2 } ] }, 'db where';

    $qb->parse_search('zx,3');
    is_deeply $qb->make_where, { -or => [ a => [ { 'LIKE', '%zx%' }, { 'LIKE', '%3%' } ] ] }, 'db where default';

    $qb->parse_search('a?');
    is_deeply $qb->make_where, { a => [ { '!=', undef } ] }, 'db not null';
    $qb->parse_search('a??');
    is_deeply $qb->make_where, { a => [ { '=', undef } ] }, 'db null';

    $qb->parse_search('a^=sss');
    is_deeply $qb->make_where, { a => [ { 'LIKE', 'sss%' } ] }, 'db starts with';
    $qb->parse_search('a!^sss');
    is_deeply $qb->make_where, { a => [ { 'NOT LIKE', 'sss%' } ] }, 'db not starts with';

    $qb->parse_search('a=1,b=x,a=2,b=y');
    is_deeply $qb->extract_search_values('b'), [ 'x', 'y' ], 'extract_search_values';
    is_deeply $qb->make_where, { a => [ { '=', 1 }, { '=', 2 } ] }, 'db where or';

    $qb->parse_search('a=x');
    is_deeply $qb->make_where, { a => [ { '=', 22 } ] }, 'enums';

    $qb->parse_search('sq>5');
    is_deeply $qb->make_where, { '(SELECT id FROM table)' => [ { '>', 5 } ] }, 'db search subquery';

    $qb->parse_search('has_v(99)');
    is_deeply $qb->make_where, \[ $sq, 99 ], 'db subquery';
    is where($qb->make_where), " WHERE ( $sq )", 'db subquery sql';

    $qb->parse_search('!has_v(99)');
    is_deeply $qb->make_where, { -not_bool => \[ $sq, 99 ] }, 'db subquery negated';
    $qb->parse_search('has_v(5),a<1');
    is_deeply $qb->make_where, { -and => [ { a => [ { '<', 1 } ] }, \[ $sq, 5 ] ] }, 'db search and subquery';
    $qb->parse_search(Encode::decode_utf8('has_v(пример)'));
    is_deeply $qb->make_where, \[ $sq, Encode::decode_utf8('пример') ], 'db subquery ru';
    $qb->parse_search(Encode::decode_utf8('has_v(x_1)'));
    is_deeply $qb->make_where, \[ $sq, 'x_1' ], 'db subquery digit underscore';
    $qb->parse_search(Encode::decode_utf8('has_v(.5)'));
    is_deeply $qb->make_where, \[ $sq, '.5' ], 'db subquery start dot';
    $qb->parse_search(Encode::decode_utf8('has_v(a-b)'));
    is_deeply $qb->make_where, \[ $sq, 'a-b' ], 'db subquery minus';
}

1;
