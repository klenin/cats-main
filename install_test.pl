use strict;
use warnings;

use File::Spec;
use FindBin;
use IPC::Cmd;

my $tmp_dir = File::Spec->catdir(File::Spec->tmpdir, 'cats');
mkdir $tmp_dir or die "mkdir failed: $!";

my $db = File::Spec->catfile($tmp_dir, 'test.fdb');
my $create_sql = File::Spec->catfile($tmp_dir, 'create.sql');

IPC::Cmd::can_run('isql-fb') or die 'Error: isql nor found';

my ($ok, $err, $full) = IPC::Cmd::run command => [ 'isql-fb', '-z', '-i' ];

# Give an invalid option, otherwise isql starts in interactive mode.
$ok || $err=~ /value 1/ or die "Error running isql: $err";
$full && $full->[0] =~ /^ISQL/ or die "isql not correct: $full->[0]";

chdir File::Spec->catdir($FindBin::Bin, 'sql', 'interbase') or die "Unable to chdir sql: $!";
{
    open my $create_template_fh, '<', 'create_db.sql.template' or die "Unable to open sql template: $!";

    open my $create_fh, '>', $create_sql or die "Unable to open create.sql: $!";

    while (<$create_template_fh>) {
        s/^(CREATE DATABASE).*$/$1 '$db';/;
        print $create_fh $_;
    }
}
($ok, $err, $full) = IPC::Cmd::run command => [ 'isql-fb', '-i', $create_sql ];
$ok or die "isql create: $err @$full";

chdir File::Spec->catdir($FindBin::Bin, 'cgi-bin', 'cats-problem', 'CATS')
    or die "Unable to chdir cats-problem: $!";
{
    -f 'Config.pm' and die 'Config already exists';
    open my $config_template_fh, '<', 'Config.pm.template' or die "Unable to open config template: $!";
    open my $config_fh, '>', 'Config.pm' or die "Unable to open config: $!";

    while (<$config_template_fh>) {
        s/dbi:Firebird/dbi:FirebirdEmbedded/;
        s/<path-to-your-database>/$db/;
        s/<your-host>//;
        s/<your-username>//;
        s/<your-password>//;
        print $config_fh $_;
    }
}
