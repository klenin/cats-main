CREATE TABLE sites (
    id       INTEGER NOT NULL PRIMARY KEY,
    name     VARCHAR(200) NOT NULL,
    region   VARCHAR(200),
    city     VARCHAR(200),
    org_name VARCHAR(200),
    address  BLOB SUB_TYPE TEXT
);
