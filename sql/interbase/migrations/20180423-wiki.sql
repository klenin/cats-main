CREATE TABLE wiki_pages (
    id         INTEGER NOT NULL PRIMARY KEY,
    name       VARCHAR(200) NOT NULL,
    contest_id INTEGER REFERENCES contests(id) ON DELETE SET NULL,
    problem_id INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    is_public  SMALLINT DEFAULT 0 NOT NULL
);

CREATE TABLE wiki_texts (
    id            INTEGER NOT NULL PRIMARY KEY,
    wiki_id       INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,
    lang          VARCHAR(20) NOT NULL,
    author_id     INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    last_modified TIMESTAMP,
    title         BLOB SUB_TYPE TEXT,
    text          BLOB SUB_TYPE TEXT
);
