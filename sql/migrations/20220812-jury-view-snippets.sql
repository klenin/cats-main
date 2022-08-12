CREATE TABLE jury_view_snippets (
    ca_id           INTEGER NOT NULL,
    problem_id      INTEGER NOT NULL,
    snippet_name    VARCHAR(200) NOT NULL,

    CONSTRAINT jury_view_ca_id_fk
        FOREIGN KEY (ca_id) REFERENCES contest_accounts(id) ON DELETE CASCADE,
    CONSTRAINT jury_view_problem_id_fk
        FOREIGN KEY (problem_id) REFERENCES problems(id) ON DELETE CASCADE
);
