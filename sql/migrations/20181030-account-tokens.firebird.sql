CREATE TABLE account_tokens (
    token       VARCHAR(40) NOT NULL PRIMARY KEY,
    account_id  INTEGER NOT NULL REFERENCES accounts(id),
    last_used   TIMESTAMP,
    referer     VARCHAR(200)
);
