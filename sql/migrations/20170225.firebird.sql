CREATE TABLE limits (
    id              INTEGER NOT NULL PRIMARY KEY,
    time_limit      FLOAT,
    memory_limit    INTEGER,
    process_limit   INTEGER,
    write_limit     INTEGER
);

ALTER TABLE contest_problems ADD
    limits_id       INTEGER REFERENCES limits(id);
ALTER TABLE reqs ADD
    limits_id       INTEGER REFERENCES limits(id);
