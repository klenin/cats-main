user=sysdba
password=Tq1f
#dbfile=/home/mike/CATS/ib_data/cats.gdb
isql=/opt/interbase/bin/isql

$isql 'webtest:cats.gdb' -user $user -password $password << EOF

SELECT * FROM messages WHERE broadcast=1;
EOF