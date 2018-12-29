ALTER TABLE contests
    ADD parent_id            INTEGER;

ALTER TABLE contests ADD CONSTRAINT contest_parent_fk
    FOREIGN KEY (parent_id) REFERENCES contests(id);
