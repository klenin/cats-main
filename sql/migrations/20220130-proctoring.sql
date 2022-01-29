CREATE TABLE proctoring (
    contest_id    INTEGER NOT NULL,
    params        CATS_TEXT,
    CONSTRAINT proctoring_contest_fk
        FOREIGN KEY (contest_id) REFERENCES contests(id) ON DELETE CASCADE
);
