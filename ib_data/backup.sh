cd ~ask/cats/ib_data
ls -t /var/backups/cats/* | tail -n 1 | xargs rm
backup_name=/var/backups/cats/`date "+cats_%Y_%m_%d.gbk"`
/usr/local/firebird2/bin/gbak -B cats $backup_name
gzip $backup_name