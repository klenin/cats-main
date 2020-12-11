ALTER TABLE contest_accounts
    ADD site_id     INTEGER REFERENCES sites(id);
ALTER TABLE contest_accounts
    ADD is_site_org SMALLINT DEFAULT 0;
ALTER TABLE contest_accounts
    ADD CONSTRAINT contest_account_site_org CHECK (is_site_org IN (0, 1));
COMMIT;

UPDATE contest_accounts SET is_site_org = 0;
COMMIT;
