ALTER TABLE tests
    ADD in_file_hash VARCHAR(100) DEFAULT NULL;
GRANT UPDATE(in_file_hash)
    ON TABLE tests TO judge;
