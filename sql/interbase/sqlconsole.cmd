@set USER=sysdba
@set PASSWORD=masterkey
@set DBFILE=d:\dev\cats\gdb\cats.gdb
@set IBASE_BIN=c:\Progra~1\Firebird\Firebird_1_5\bin
@set ISQL=%IBASE_BIN%\isql
%ISQL% -user %USER% -password %PASSWORD% %DBFILE% < %1