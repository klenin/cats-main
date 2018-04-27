CREATE TABLE wiki_pages (
    id         INTEGER NOT NULL PRIMARY KEY,
    name       VARCHAR(200) NOT NULL,
    contest_id INTEGER,
    problem_id INTEGER,
    is_public  SMALLINT DEFAULT 0 NOT NULL,

    CONSTRAINT wiki_pages_contests_fk
        FOREIGN KEY (contest_id) REFERENCES contests(id) ON DELETE SET NULL,
    CONSTRAINT wiki_pages_problem_fk
        FOREIGN KEY (problem_id) REFERENCES problems(id) ON DELETE CASCADE
);

CREATE TABLE wiki_texts (
    id            INTEGER NOT NULL PRIMARY KEY,
    wiki_id       INTEGER NOT NULL,
    lang          VARCHAR(20) NOT NULL,
    author_id     INTEGER,
    last_modified TIMESTAMP,
    title         BLOB SUB_TYPE TEXT,
    text          BLOB SUB_TYPE TEXT,

    CONSTRAINT wiki_texts_wiki_fk
        FOREIGN KEY (wiki_id) REFERENCES wiki_pages(id) ON DELETE CASCADE,
    CONSTRAINT wiki_texts_author_fk
        FOREIGN KEY (author_id) REFERENCES accounts(id) ON DELETE SET NULL
);
