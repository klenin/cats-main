user=sysdba
password=masterkey
dbfile=./../../ib_data/cats.gdb
isql=/opt/interbase/bin/isql
$isql -user $user -password $password $dbfile << EOF

--ALTER TABLE messages ADD broadcast INTEGER;
UPDATE messages SET broadcast=0;
COMMIT;
EOF

