CREATE TABLE solution_output
(
    req_id          INTEGER NOT NULL,
    test_rank       INTEGER NOT NULL,
    output          BLOB NOT NULL,
    output_size     INTEGER NOT NULL,
    create_time     TIMESTAMP NOT NULL,

    CONSTRAINT so_fk FOREIGN KEY (req_id, test_rank) REFERENCES req_details(req_id, test_rank) ON DELETE CASCADE
);

ALTER TABLE problems ADD
    save_output_prefix INTEGER;
