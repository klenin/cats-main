user=sysdba
password=masterkey
dbfile=./../../ib_data/cats.gdb
isql=/opt/interbase/bin/isql

$isql -user $user -password $password $dbfile << EOF

-- ALTER TABLE contest_accounts ADD is_virtual INTEGER;
-- ALTER TABLE contest_accounts ADD diff_time FLOAT;
-- ALTER TABLE contest_accounts ALTER COLUMN diff_time TYPE FLOAT;
-- ALTER TABLE contest_accounts ALTER diff_time TO diff_time2;
-- UPDATE contest_accounts SET diff_time=diff_time2;
-- ALTER TABLE contest_accounts DROP diff_time2;
--UPDATE contest_accounts SET diff_time=0;
COMMIT;
EOF
