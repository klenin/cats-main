#!/bin/bash
ORACLE_BASE=/oracle/app/oracle; export ORACLE_BASE
ORACLE_HOME=$ORACLE_BASE/product/8.1.7; export ORACLE_HOME
ORACLE_SID=orcl; export ORACLE_SID
PATH=$PATH:$ORACLE_HOME/bin; export PATH
CLASSPATH=.:$ORACLE_HOME/jdbc/lib/classes111.zip; export CLASSPATH
LD_LIBRARY_PATH=$ORACLE_HOME/lib; export LD_LIBRARY_PATH

ORA_NLS33=$ORACLE_HOME/ocommon/nls/admin/data; export ORA_NLS33
# NLS_LANG=american; export NLS_LANG

NLS_LANG=american_america.cl8mswin1251