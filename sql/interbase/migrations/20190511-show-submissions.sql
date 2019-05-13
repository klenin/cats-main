ALTER TABLE contests
    ADD pub_reqs_date TIMESTAMP;

ALTER TABLE contests
    ADD show_all_for_solved  SMALLINT DEFAULT 0 NOT NULL;
