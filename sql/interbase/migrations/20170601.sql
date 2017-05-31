ALTER TABLE contests
    ADD pinned_judges_only   SMALLINT DEFAULT 0 NOT NULL;

ALTER TABLE contests ADD CONSTRAINT chk_pinned_judges_only
    CHECK (pinned_judges_only IN (0, 1));
