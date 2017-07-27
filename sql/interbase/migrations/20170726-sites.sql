CREATE TABLE sites (
    id       INTEGER NOT NULL PRIMARY KEY,
    name     VARCHAR(200) NOT NULL,
    region   VARCHAR(200),
    city     VARCHAR(200),
    org_name VARCHAR(200),
    address  BLOB SUB_TYPE TEXT
);

CREATE TABLE contest_sites (
    contest_id  INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,
    site_id  INTEGER NOT NULL REFERENCES sites(id)
);
ALTER TABLE contest_sites
    ADD CONSTRAINT contest_sites_pk PRIMARY KEY (contest_id, site_id);
