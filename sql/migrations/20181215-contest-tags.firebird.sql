CREATE TABLE contest_tags (
    id       INTEGER NOT NULL PRIMARY KEY,
    name     VARCHAR(100) NOT NULL
);

CREATE TABLE contest_contest_tags (
    contest_id   INTEGER NOT NULL,
    tag_id       INTEGER NOT NULL,
    CONSTRAINT contest_contest_tags_contest_fk
        FOREIGN KEY (contest_id) REFERENCES contests(id) ON DELETE CASCADE,
    CONSTRAINT contest_contest_tags_tag_fk
        FOREIGN KEY (tag_id) REFERENCES contest_tags(id) ON DELETE CASCADE
);
