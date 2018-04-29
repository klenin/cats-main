CREATE TABLE jobs (
    id          INTEGER NOT NULL PRIMARY KEY,
    req_id      INTEGER NOT NULL,
    parent_id   INTEGER,
    type        INTEGER NOT NULL,
    state       INTEGER NOT NULL,
    create_time TIMESTAMP,
    start_time  TIMESTAMP,
    finish_time TIMESTAMP,
    judge_id    INTEGER,
    testsets    VARCHAR(200),

    CONSTRAINT jobs_requests_id
        FOREIGN KEY (req_id) REFERENCES reqs(id) ON DELETE CASCADE,
    CONSTRAINT parent_job_id
        FOREIGN KEY (parent_id) REFERENCES jobs(id) ON DELETE CASCADE,
    CONSTRAINT job_judge_id
        FOREIGN KEY (judge_id) REFERENCES judges(id) ON DELETE SET NULL
);

CREATE TABLE jobs_queue (
    id INTEGER NOT NULL PRIMARY KEY
);
