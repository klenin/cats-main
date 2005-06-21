cd ~mike/CATS/ib_data
ls -t backup/* | tail -n 1 | xargs rm
backup_name=backup/`date "+cats_%Y_%m_%d.gbk"`
/opt/interbase/bin/gbak -B cats.gdb $backup_name
gzip $backup_name