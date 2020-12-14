package CATS::Deploy;

use strict;
use warnings;

use File::Spec;
use FindBin qw($Bin);
use IPC::Cmd;

use constant FS => 'File::Spec';

sub substitute_template_parameters {
    my ($fin, $fout, $args) = @_;
    open my $fin_fh, '<', $fin or die "Unable to open $fin: $!";
    open my $fout_fh, '>', $fout or die "Unable to open $fout: $!";
    while (<$fin_fh>) {
        for my $k (keys %$args) {
            s/$k/$args->{$k}/g;
        }
        print $fout_fh $_;
    }
}

sub run_sql {
    my ($file, $quiet) = @_;
    my $cmd;
    if ($file =~ /interbase/) {
        my $isql = $^O eq 'Win32' ? 'isql' : 'isql-fb';
        IPC::Cmd::can_run($isql) or die "Error: $isql not found";
        $cmd = [$isql, '-i', $file];
    } elsif ($file =~ /postgres/) {
        die 'Todo: psql windows command' if $^O eq 'Win32';
        IPC::Cmd::can_run('psql') or die 'Error: psql not found';
        $cmd = ['psql', '-U', 'postgres', '-f', $file];
    }
    push(@$cmd, '-q') if $quiet;
    my ($ok, $err, $full) = IPC::Cmd::run command => $cmd;
    $ok or die join "\n", $err, @$full;
    print '-' x 20, "\n", @$full if !$quiet;
}

sub create_db {
    my ($sql_subdir, $dbname, $user, $password, %p) = @_;

    my $quiet = $p{quiet} // 0;
    my $no_run = $p{no_run} // 0;
    my $dir = $p{dir};
    my $init_config = $p{init_config} // 0;
    my $driver = $p{driver};
    my $host = $p{host};

    my ($next_id, $path);
    if ($sql_subdir eq 'interbase') {
        $next_id = 'GEN_ID(key_seq, 1)';
        $path = $dir ? FS->catfile($dir, $dbname . '.fdb') : $dbname;
        $driver //= 'Firebird';
    } elsif ($sql_subdir eq 'postgres') {
        $next_id = "NEXTVAL('key_seq')";
        $path = $dbname;
        print STDERR 'Warning: Setting directory currently has no effect when PostgreSQL is selected'
            if $dir && !$quiet;
        $driver //= 'Pg';
    } else {
        die "Cannot determine DBMS for 'sql/$sql_subdir' directory.";
    }

    my $sql_dir = FS->catdir($Bin, 'sql');
    substitute_template_parameters(
        FS->catfile($sql_dir, 'common', 'init_data.sql.template'),
        FS->catfile($sql_dir, $sql_subdir, 'init_data.sql'),
        { '<NEXT_ID>' => $next_id },
    );

    my $create_db_sql = FS->catfile($sql_dir, $sql_subdir, 'create_db.sql');
    substitute_template_parameters($create_db_sql . '.template', $create_db_sql, {
        '<your-username>' => $user,
        '<your-password>' => $password,
        '<path-to-your-database>' => $path,
    });

    my $config_pm = FS->catfile($Bin, qw(cgi-bin cats-problem CATS Config.pm));
    die 'Host is required' if !$host && $init_config;
    substitute_template_parameters($config_pm . '.template', $config_pm, {
        '<your-db-name>' => $path,
        '<your-db-driver>' => $driver,
        '<your-db-username>' => $user,
        '<your-db-password>' => $password,
        '<your-db-host>' => $host,
    }) if $init_config;

    if (!$no_run) {
        chdir File::Spec->catdir($sql_dir, $sql_subdir) or die "Unable to chdir 'sql/$sql_subdir': $!";
        run_sql($create_db_sql, $quiet);
    }

    1;
}

1;
