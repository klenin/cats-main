CREATE TABLE job_sources (
    job_id  INTEGER NOT NULL,
    src     CATS_BLOB,
    CONSTRAINT job_sources_job_id_fk
        FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
);

GRANT SELECT ON TABLE job_sources TO judge;
