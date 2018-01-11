INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 120, 'Rust', 'rs', '', '^\s+-->\s~FILE~:~LINE~:~POS~');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 404, 'Go', 'go', '', '^~FILE~:~LINE~:~POS~:');
COMMIT;
