CREATE TABLE contest_problem_des (
    cp_id  INTEGER NOT NULL,
    de_id  INTEGER NOT NULL,

    CONSTRAINT contest_problem_de_pk
        PRIMARY KEY (cp_id, de_id),
    CONSTRAINT contest_problem_de_cp_fk
        FOREIGN KEY (cp_id) REFERENCES contest_problems(id) ON DELETE CASCADE,
    CONSTRAINT contest_problem_de_de_fk
        FOREIGN KEY (de_id) REFERENCES default_de(id) ON DELETE CASCADE
);
