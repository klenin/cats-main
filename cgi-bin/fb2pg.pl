use v5.10;
use strict;
use warnings;

use DBI;
use Encode;
use File::Spec;
use FindBin;
use Getopt::Long;
use List::Util qw(first);

use lib File::Spec->catdir($FindBin::Bin, 'cats-problem');
use lib $FindBin::Bin;

use CATS::Config;
use CATS::Deploy;

sub usage {
    print STDERR 'CATS firebird to postgres conversion tool
Usage:
  [--help]
  [--fbdb=<name>]              Firebird database name (default: from config)
  [--fblogin=<login>]          Firebird database owner login (default: from config)
  [--fbpassword=<password>]    Firebird database owner password (default: from config)
  [--fbhost=<host>]            Firebird database host (default: from config)
  [--pgdb=<name>]              Postgres database name (default: derived from config)
  [--pglogin=<login>]          Postgres database owner login (default: derived from config)
  [--pgpassword=<password>]    Postgres database owner password (default: derived from config)
  [--start-from=<name>]        Start from table <name>
  [--clear]                    Clear table before migration 
  [--single-table=<name>]      Migrate single table <name>
';
    exit;
}

my $db = $CATS::Config::db;

GetOptions(
    help => \(my $help = 0),
    'fbdb=s' => \(my $fbdb = $db->{name}),
    'fblogin=s' => \(my $fblogin = $db->{user}),
    'fbpassword=s' => \(my $fbpassword = $db->{password}),
    'fbhost=s' => \(my $fbhost = $db->{host}),
    'pgdb=s' => \(my $pgdb = $db->{name}),
    'pglogin=s' => \(my $pglogin = $db->{user}),
    'pgpassword=s' => \(my $pgpassword = $db->{password}),
    'pghost=s' => \(my $pghost = $db->{host}),
    'start-from=s' => \(my $start_from),
    clear => \(my $clear = 0),
    'single-table=s' => \(my $single_table),
) or usage;

sub fb_connect {
    DBI->connect(
        "dbi:Firebird:dbname=$fbdb;host=$fbhost;ib_charset=UTF8;ib_role=",
        $fblogin, $fbpassword,
        {
            LongReadLen => 10*1024*1024,
            RaiseError => 1,
            FetchHashKeyName => 'NAME_lc',
            ib_timestampformat => '%Y-%m-%d %H:%M:00+10',
            ib_dateformat => '%Y-%m-%d',
        }
    ) or die "Cannot connect to firebird database: $DBI::errstr";
}

sub pg_try_connect {
    eval {
        DBI->connect(
            "dbi:Pg:dbname=$pgdb;host=$pghost;",
            $pglogin, $pgpassword,
            { AutoCommit => 0, RaiseError => 1, PrintError => 0 }
        );
    }
}

sub pg_connect_or_create {
    my $pg = pg_try_connect;
    if (!$pg) {
        CATS::Deploy::create_db('postgres', $pgdb, $pglogin, $pgpassword,
            host => $pghost, pg_auth_type => 'peer', quiet => 1
        );
        $clear = 1; # Database is not empty when created.
        $pg = pg_try_connect or die "Cannot connect to postgres database: $DBI::errstr";
    }
    $pg;
}

sub find_table_index {
    my ($tables, $name) = @_;
    first { $tables->[$_] eq uc($name) } 0..$#$tables
        or die "Unknown table $name";
}

sub bind_row {
    my ($pg, $sth, $row, $field_info) = @_;
    my ($BLOB_SUBTYPE, $VARCHAR, $PG_BYTEA) = (261, 37, 17);
    for my $i (0 .. $#$field_info) {
        my $fi = $field_info->[$i];
        my $data = $row->[$i];
        my $att = {};
        if ($fi->{type} == $BLOB_SUBTYPE && $fi->{subtype} == 0) {
            $att = { pg_type => $PG_BYTEA };
        } elsif ($fi->{type} == $VARCHAR) {
            $data = Encode::decode_utf8($data);
        } 
        $sth->bind_param($i + 1, $data, $att);
    }
}

sub handle_insert_error {
    my ($row_no, $row, $field_info) = @_;
    my $row_info = $field_info->[0]->{name} eq 'ID'
        ? "id: $row->[0], number: $row_no" : "number: $row_no";
    die "Failed to insert row ($row_info): $@\n";
}

sub migrate_table {
    my ($fb, $pg, $table) = @_;
    say $table;

    my ($num_rows) = $fb->selectrow_array(qq~SELECT COUNT(*) FROM $table~, undef);
    if ($num_rows == 0) {
        say "  EMPTY\n  OK";
        return;
    }

    if ($clear) {
        say '  CLEANING...';
        $pg->do(qq~DELETE FROM $table~);
    }

    my $field_info = $fb->selectall_arrayref(q~
        SELECT
            TRIM(RF.RDB$FIELD_NAME) as name,
            F.RDB$FIELD_TYPE AS type,
            F.RDB$FIELD_SUB_TYPE AS subtype
        FROM RDB$RELATION_FIELDS RF, RDB$FIELDS F
        WHERE 
            RF.RDB$RELATION_NAME = ? AND
            F.RDB$FIELD_NAME = RF.RDB$FIELD_SOURCE AND
            RF.RDB$SYSTEM_FLAG = 0
        ORDER BY RDB$FIELD_POSITION~, { Slice => {} }, $table);

    my $fields = join ',', map { $_->{name} } @$field_info;
    my $values = join ',', map { '?' } @$field_info; 
    my $insert_sth = $pg->prepare(qq~INSERT INTO $table ($fields) VALUES ($values)~);
    my $select_sth = $fb->prepare(qq~SELECT $fields FROM $table~);
    $select_sth->execute;

    my $batch_size = 256;
    for my $i (1 .. $num_rows) {
        my $row = $select_sth->fetchrow_arrayref or die 'Expected row';
        eval {
            bind_row($pg, $insert_sth, $row, $field_info);
            $insert_sth->execute; 
        } or handle_insert_error($i, $row, $field_info);

        if (($i % $batch_size == 0) or ($i == $num_rows)) {
            $pg->commit;
            say "  $i / $num_rows";
        }
    }
    say '  OK';
}

sub migrate_generators {
    my ($fb, $pg) = @_;
    say "\nMigrating generators:";

    my $generators = $fb->selectcol_arrayref(q~
        SELECT TRIM(RDB$GENERATOR_NAME) AS name
        FROM RDB$GENERATORS
        WHERE RDB$SYSTEM_FLAG = 0
        ORDER BY name~);

    for my $generator (@$generators) {
        say $generator;
        my ($val) = $fb->selectrow_array(qq~SELECT GEN_ID($generator, 0) FROM RDB\$DATABASE~);
        $val = 1 if $val == 0; # Default minimal generator value is 1 in postgres.
        $pg->do(qq~ALTER SEQUENCE $generator RESTART WITH $val~);
        say '  OK';
    }
    $pg->commit;
}

sub migrate_all {
    my ($fb, $pg) = @_;

    my $tables = $fb->selectcol_arrayref(q~
        SELECT TRIM(RDB$RELATION_NAME) AS name
        FROM RDB$RELATIONS
        WHERE RDB$SYSTEM_FLAG = 0
        ORDER BY name~);

    if ($single_table) {
        my $i = find_table_idx($tables, $single_table);
        migrate_table($fb, $pg, $tables->[$i]);
        return;
    }

    my $start = 0;
    if ($start_from) {
        $start = find_table_idx($tables, $start_from);
        $pg->do(qq~DELETE FROM $start_from~);
    }
    say "\nMigrating tables:";
    migrate_table($fb, $pg, $tables->[$_]) for $start..$#$tables;
    migrate_generators($fb, $pg);
}

sub main {
    my $fb = fb_connect;
    my $pg = pg_connect_or_create;
    say "Firebird database: $fbdb, host: $fbhost";
    say "Postgres database: $pgdb, host: $pghost";

    # Disable foreign key checks (requires super user permissions). 
    $pg->do(q~SET SESSION_REPLICATION_ROLE TO REPLICA~);
    eval {
        migrate_all($fb, $pg);
    };
    if ($@) {
        $pg->rollback;
        print STDERR "$@";
    }
    $pg->do(q~SET SESSION_REPLICATION_ROLE TO DEFAULT~);

    $fb->disconnect;
    $pg->disconnect;
    say "\nOK";
    1;
}

$help ? usage : main;
