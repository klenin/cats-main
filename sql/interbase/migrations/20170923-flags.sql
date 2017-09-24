ALTER TABLE contests ADD
    show_flags           SMALLINT DEFAULT 0 CHECK (show_flags IN (0, 1));
