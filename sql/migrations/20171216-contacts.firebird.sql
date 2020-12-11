CREATE TABLE contact_types (
    id      INTEGER NOT NULL PRIMARY KEY,
    name    VARCHAR(100) NOT NULL,
    url     VARCHAR(100),
    icon    BLOB
);

CREATE TABLE contacts (
    id              INTEGER NOT NULL PRIMARY KEY,
    account_id      INTEGER REFERENCES accounts(id) ON DELETE CASCADE,
    contact_type_id INTEGER REFERENCES contact_types(id) ON DELETE CASCADE,
    handle          VARCHAR(100) NOT NULL,
    is_public       SMALLINT DEFAULT 0,
    is_actual       SMALLINT DEFAULT 1
);
