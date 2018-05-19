CREATE TABLE logs (
    id      INTEGER NOT NULL PRIMARY KEY,
    dump    BLOB,
    job_id  INTEGER,

    CONSTRAINT logs_job_id_fk FOREIGN KEY (job_id)
        REFERENCES jobs(id) ON DELETE CASCADE
);
