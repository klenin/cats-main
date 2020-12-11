ALTER TABLE tests ADD
    in_file_size    INTEGER;

ALTER TABLE tests ADD
    out_file_size    INTEGER;

ALTER TABLE problems ADD
    save_input_prefix INTEGER;

ALTER TABLE problems ADD
    save_answer_prefix INTEGER;
