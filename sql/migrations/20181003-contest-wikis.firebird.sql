CREATE TABLE contest_wikis (
    id         INTEGER NOT NULL PRIMARY KEY,
    contest_id INTEGER NOT NULL,
    wiki_id    INTEGER NOT NULL,
    allow_edit SMALLINT NOT NULL,
    ordering   SMALLINT NOT NULL,
    CONSTRAINT contest_wikis_contest_fk
        FOREIGN KEY (contest_id) REFERENCES contests(id) ON DELETE CASCADE,
    CONSTRAINT contest_wikis_wiki_fk
        FOREIGN KEY (wiki_id) REFERENCES wiki_pages(id) ON DELETE CASCADE
);
