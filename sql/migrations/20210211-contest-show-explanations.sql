ALTER TABLE contests
    ADD show_explanations    SMALLINT DEFAULT 0 NOT NULL CHECK (show_explanations IN (0, 1));
COMMIT;

UPDATE contests SET show_explanations = show_packages;
COMMIT;
