CREATE TABLE jobs (
    id          INTEGER NOT NULL PRIMARY KEY,
    req_id      INTEGER,
    parent_id   INTEGER,
    type        INTEGER NOT NULL,
    state       INTEGER NOT NULL,
    create_time TIMESTAMP,
    start_time  TIMESTAMP,
    finish_time TIMESTAMP,
    judge_id    INTEGER,
    testsets    VARCHAR(200),

    CONSTRAINT jobs_req_id_fk
        FOREIGN KEY (req_id) REFERENCES reqs(id) ON DELETE CASCADE,
    CONSTRAINT jobs_parent_id_fk
        FOREIGN KEY (parent_id) REFERENCES jobs(id) ON DELETE CASCADE,
    CONSTRAINT jobs_judge_id_fk
        FOREIGN KEY (judge_id) REFERENCES judges(id) ON DELETE SET NULL
);

CREATE TABLE jobs_queue (
    id INTEGER NOT NULL PRIMARY KEY,
    CONSTRAINT jobs_queue_id
        FOREIGN KEY (id) REFERENCES jobs(id) ON DELETE CASCADE
);

GRANT SELECT ON TABLE jobs TO judge;
GRANT SELECT ON TABLE jobs_queue TO judge;

GRANT UPDATE(state, start_time, finish_time, judge_id)
    ON TABLE jobs TO judge;

GRANT DELETE
    ON TABLE jobs_queue TO judge;
