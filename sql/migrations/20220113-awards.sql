CREATE TABLE awards (
    id          INTEGER NOT NULL PRIMARY KEY,
    contest_id  INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,
    name        VARCHAR(200) NOT NULL,
    descr       CATS_TEXT,
    color       VARCHAR(50),
    is_public   SMALLINT DEFAULT 0 NOT NULL
);

CREATE TABLE contest_account_awards (
    award_id    INTEGER NOT NULL REFERENCES awards(id) ON DELETE CASCADE,
    ca_id       INTEGER NOT NULL REFERENCES contest_accounts(id) ON DELETE CASCADE,
    ts          CATS_TIMESTAMP NOT NULL
);
