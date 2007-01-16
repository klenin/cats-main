cd ~ask/cats/ib_data
ls -t backup/* | tail -n 1 | xargs rm
backup_name=backup/`date "+cats_%Y_%m_%d.gbk"`
/usr/local/firebird/bin/gbak -B cats $backup_name
gzip $backup_name