CREATE TABLE acc_groups (
    id          INTEGER NOT NULL PRIMARY KEY,
    name        VARCHAR(200),
    description BLOB SUB_TYPE TEXT
);

CREATE TABLE acc_group_accounts (
    acc_group_id    INTEGER NOT NULL,
    account_id      INTEGER NOT NULL,
    is_admin        SMALLINT DEFAULT 0,
    is_hidden       SMALLINT DEFAULT 0,
    date_start      DATE NOT NULL,
    date_finish     DATE,
    CONSTRAINT acc_group_accounts_acc_group_fk
        FOREIGN KEY (acc_group_id) REFERENCES acc_groups(id) ON DELETE CASCADE,
    CONSTRAINT acc_group_accounts_account_fk
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
    CONSTRAINT acc_group_accounts_pk PRIMARY KEY (acc_group_id, account_id)
);

CREATE TABLE acc_group_contests (
    acc_group_id    INTEGER NOT NULL,
    contest_id      INTEGER NOT NULL,
    CONSTRAINT acc_group_contests_acc_group_fk
        FOREIGN KEY (acc_group_id) REFERENCES acc_groups(id) ON DELETE CASCADE,
    CONSTRAINT acc_group_contests_contest_fk
        FOREIGN KEY (contest_id) REFERENCES contests(id) ON DELETE CASCADE,
    CONSTRAINT acc_group_contests_pk PRIMARY KEY (acc_group_id, contest_id)
);
