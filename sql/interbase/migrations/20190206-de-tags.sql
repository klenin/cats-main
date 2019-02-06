CREATE TABLE de_tags (
    id            INTEGER NOT NULL PRIMARY KEY,
    name          VARCHAR(200) NOT NULL,
    description   BLOB SUB_TYPE TEXT
);

CREATE INDEX de_tags_name_idx ON de_tags(name);

CREATE TABLE de_de_tags (
    de_id         INTEGER NOT NULL,
    tag_id        INTEGER NOT NULL,
    CONSTRAINT de_de_tags_de_fk
        FOREIGN KEY (de_id) REFERENCES default_de(id) ON DELETE CASCADE,
    CONSTRAINT de_de_tags_tag_fk
        FOREIGN KEY (tag_id) REFERENCES de_tags(id) ON DELETE CASCADE
);

CREATE TABLE contest_de_tags (
    contest_id    INTEGER NOT NULL,
    tag_id        INTEGER NOT NULL,
    CONSTRAINT contest_de_tags_de_fk
        FOREIGN KEY (contest_id) REFERENCES contests(id) ON DELETE CASCADE,
    CONSTRAINT contest_de_tags_tag_fk
        FOREIGN KEY (tag_id) REFERENCES de_tags(id) ON DELETE CASCADE
);
