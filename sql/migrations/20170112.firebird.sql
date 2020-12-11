ALTER TABLE contests ADD
    short_descr   BLOB SUB_TYPE TEXT;
ALTER TABLE contests ALTER short_descr POSITION 3;
