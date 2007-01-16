user=sysdba
password=masterkey
#dbfile=./../../ib_data/cats.gdb
dbfile=/home/mike/CATS/ib_data/cats.gdb
isql=/opt/interbase/bin/isql

$isql -user $user -password $password $dbfile << EOF

COMMIT;
EOF
