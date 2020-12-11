ALTER TABLE judges
    ADD version VARCHAR(100);

GRANT UPDATE(version)
    ON TABLE judges TO judge;
