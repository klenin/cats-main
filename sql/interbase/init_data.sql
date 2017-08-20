INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 1, 'Do not compile this file', 'h;inc');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 101, 'Cross-platform C/C++ compiler', 'cpp;c');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 102, 'GNU C++', 'cpp;c;cxx');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 103, 'MS Visual C++', 'cpp;c');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 104, 'Borland C++ 3.1', 'cpp;c');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 201, 'Borland Pascal', 'pas');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 202, 'Free Pascal', 'pas;pp');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 204, 'Free Pascal in Delphi mode', 'dpr');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 301, 'Quick Basic 4.5', 'bas');
INSERT INTO default_de (id, code, description, file_ext, in_contests) VALUES (GEN_ID(key_seq, 1), 401, 'JavaScript', 'js', 0);

INSERT INTO contests(id, title, ctype, start_date) VALUES(1, 'Турнир', 1, CURRENT_DATE - 100);
INSERT INTO accounts(id, login, passwd, srole) VALUES(2, 'root', 'root', 0);
INSERT INTO accounts(id, login, passwd, srole) VALUES(5, 'fox', 'fox', 1);
/* See $cats::anonymous_login */
INSERT INTO accounts(id, login, passwd, srole, locked) VALUES(6, 'anonymous', '', 0, 1);
INSERT INTO contest_accounts(id, contest_id, account_id, is_jury) VALUES (3, 1, 2, 1);
INSERT INTO judges(id, nick, pin_mode, account_id) VALUES (4, 'fox', 3, 5);
