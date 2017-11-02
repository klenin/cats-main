INSERT INTO default_de (id, code, description, file_ext)
    VALUES (GEN_ID(key_seq, 1), 1, 'Do not compile this file', 'h;inc');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 101, 'Cross-platform C/C++ compiler', 'cc', 'cpp', '^~FILE~:~LINE~:~POS~:');

INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 102, 'GNU C++', 'cc;cxx', 'cpp', '^~FILE~:~LINE~:~POS~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 103, 'MS Visual C++', 'cpp', 'cpp', '^~FILE~\(~LINE~\)\s?:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 104, 'Borland C++ 3.1', '', 'cpp', 'Error\s~FILE~\s~LINE~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 105, 'GNU C', 'c', 'cpp', '^~FILE~:~LINE~:~POS~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 106, 'LLVM/CLang', '', 'cpp', '^~FILE~:~LINE~:~POS~:');

INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 201, 'Borland Pascal', '', 'delphi', '\(~LINE~\):\sError');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 202, 'Free Pascal', 'lpr;pp', 'delphi', '^~FILE~\(~LINE~,~POS~\)\s');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 204, 'Free Pascal in Delphi mode', 'dpr', 'delphi', '^~FILE~\(~LINE~,~POS~\)\s');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 205, 'PascalABC', '', 'delphi', '^\[~LINE~,~POS~\]\s~FILE~:');

INSERT INTO default_de (id, code, description, file_ext, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 301, 'Quick Basic 4.5', 'qb', 'vb');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 302, 'Free Basic', 'bas', 'vb', '^~FILE~\(~LINE~\)\s');

INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 401, 'Java', 'java', 'java', '^~FILE~:~LINE~:\s');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 402, 'Microsoft Visual C#', 'cs', 'cSharp', '^~FILE~\(~LINE~,~POS~\):');

INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 501, 'Perl', 'pl', 'perl', 'at\s~FILE~\sline\s~LINE~');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 502, 'Python', 'py', 'python', '^\s+File\s"~FILE~",\sline\s~LINE~');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 503, 'Haskell', 'hs', '', '^~FILE~:~LINE~:~POS~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 504, 'Ruby', 'rb', 'ruby', '');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 505, 'PHP', 'php', 'php', 'in\s~FILE~\son\sline\s~LINE~');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 506, 'Erlang', 'erl', 'erlang', '\/~FILE~:~LINE~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 507, 'NodeJS', 'js', 'jScript', '[\\\/]~FILE~:~LINE~');

INSERT INTO contests(id, title, ctype, start_date) VALUES(1, 'Турнир', 1, CURRENT_DATE - 100);
INSERT INTO accounts(id, login, passwd, srole) VALUES(2, 'root', 'root', 0);
INSERT INTO accounts(id, login, passwd, srole) VALUES(5, 'fox', 'fox', 1);
/* See $cats::anonymous_login */
INSERT INTO accounts(id, login, passwd, srole, locked) VALUES(6, 'anonymous', '', 0, 1);
INSERT INTO contest_accounts(id, contest_id, account_id, is_jury) VALUES (3, 1, 2, 1);
INSERT INTO judges(id, nick, pin_mode, account_id) VALUES (4, 'fox', 3, 5);
