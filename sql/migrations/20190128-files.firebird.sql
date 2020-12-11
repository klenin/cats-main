CREATE TABLE files (
    id            INTEGER NOT NULL PRIMARY KEY,
    name          VARCHAR(200) NOT NULL,
    guid          VARCHAR(50) NOT NULL,
    file_size     INTEGER NOT NULL,
    description   BLOB SUB_TYPE TEXT
);
