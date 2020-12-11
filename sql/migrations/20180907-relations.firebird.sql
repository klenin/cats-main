CREATE TABLE relations (
    id       INTEGER NOT NULL PRIMARY KEY,
    rel_type INTEGER NOT NULL, /* enum */
    from_id  INTEGER NOT NULL,
    to_id    INTEGER NOT NULL,
    from_ok  SMALLINT NOT NULL,
    to_ok    SMALLINT NOT NULL,
    ts       TIMESTAMP,

    CONSTRAINT relations_from_id_fk
        FOREIGN KEY (from_id) REFERENCES accounts(id) ON DELETE CASCADE,
    CONSTRAINT relations_to_id_fk
        FOREIGN KEY (to_id) REFERENCES accounts(id) ON DELETE CASCADE
);
