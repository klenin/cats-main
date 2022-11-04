CREATE TABLE topics (
    id          INTEGER NOT NULL PRIMARY KEY,
    contest_id  INTEGER NOT NULL,
    name        VARCHAR(200) NOT NULL,
    description CATS_TEXT,
    code_prefix VARCHAR(100) NOT NULL,
    is_hidden   SMALLINT DEFAULT 0,
    CONSTRAINT topic_contest_fk
        FOREIGN KEY (contest_id) REFERENCES contests(id) ON DELETE CASCADE
);
