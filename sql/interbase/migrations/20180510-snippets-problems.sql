ALTER TABLE jobs
    ADD account_id INTEGER;
ALTER TABLE jobs
    ADD CONSTRAINT jobs_account_id_fk FOREIGN KEY (account_id)
    REFERENCES accounts(id) ON DELETE CASCADE;

ALTER TABLE jobs
    ADD contest_id INTEGER;
ALTER TABLE jobs
    ADD CONSTRAINT jobs_contest_id_fk FOREIGN KEY (contest_id)
    REFERENCES contests(id) ON DELETE CASCADE;

ALTER TABLE jobs
    ADD problem_id INTEGER;
ALTER TABLE jobs
    ADD CONSTRAINT jobs_problem_id_fk FOREIGN KEY (problem_id)
    REFERENCES problems(id) ON DELETE CASCADE;

CREATE TABLE problem_snippets (
    problem_id      INTEGER NOT NULL,
    snippet_name    VARCHAR(200) NOT NULL,
    generator_id    INTEGER,
    in_file         BLOB SUB_TYPE TEXT,

    CONSTRAINT problem_snippets_problem_id_fk
        FOREIGN KEY (problem_id) REFERENCES problems(id) ON DELETE CASCADE,
    CONSTRAINT pr_snippets_generator_id_fk
        FOREIGN KEY (generator_id) REFERENCES problem_sources(id) ON DELETE CASCADE,

    CONSTRAINT problem_snippets_uniq UNIQUE (problem_id, snippet_name)
);
