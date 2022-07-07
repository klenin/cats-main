#!/usr/bin/env bash

# bash crontab_backup.bash | sudo crontab -

CATS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # assume, that script is in a root dir of repo
ME=$(whoami)

CRONTAB=$(cat <<EOF
23 6 * * 0,3 perl $CATS_ROOT/cgi-bin/backup.pl --report=mail --quiet --zip --chown=$ME --max=5
23 6 * * 1,4 perl $CATS_ROOT/cgi-bin/backup_repos.pl --report=mail --quiet --zip --chown=$ME --max=5
11 23 * * * perl $CATS_ROOT/cgi-bin/health_report.pl --output=mail
EOF
)

echo -e "$CRONTAB"
