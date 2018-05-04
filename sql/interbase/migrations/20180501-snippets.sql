CREATE TABLE snippets (
    id              INTEGER NOT NULL PRIMARY KEY,
    account_id      INTEGER NOT NULL,
    problem_id      INTEGER NOT NULL,
    contest_id      INTEGER NOT NULL,
    name            VARCHAR(200) NOT NULL,
    text            BLOB SUB_TYPE TEXT,

    CONSTRAINT snippets_account_id_fk
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
    CONSTRAINT snippets_problem_id_fk
        FOREIGN KEY (problem_id) REFERENCES problems(id) ON DELETE CASCADE,
    CONSTRAINT snippets_contest_id_fk
        FOREIGN KEY (contest_id) REFERENCES contests(id) ON DELETE CASCADE,

    CONSTRAINT snippets_uniq UNIQUE (account_id, problem_id, contest_id, name)
);
