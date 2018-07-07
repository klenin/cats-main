INSERT INTO default_de (id, code, description, file_ext)
    VALUES (GEN_ID(key_seq, 1), 1, 'Do not compile this file', 'h;inc');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 101, 'Cross-platform C/C++ compiler', 'cc', 'c_cpp', '^~FILE~:~LINE~:~POS~:');

INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 102, 'GNU C++', 'cc;cxx', 'c_cpp', '^~FILE~:~LINE~:~POS~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 103, 'MS Visual C++', 'cpp', 'c_cpp', '^~FILE~\(~LINE~\)\s?:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 104, 'Borland C++ 3.1', '', 'c_cpp', 'Error\s~FILE~\s~LINE~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 105, 'GNU C', 'c', 'c_cpp', '^~FILE~:~LINE~:~POS~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 106, 'LLVM/CLang', '', 'c_cpp', '^~FILE~:~LINE~:~POS~:');

INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 120, 'Rust', 'rs', 'rust', '^\s+-->\s~FILE~:~LINE~:~POS~');

INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 201, 'Borland Pascal', '', 'pascal', '\(~LINE~\):\sError');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 202, 'Free Pascal', 'lpr;pp', 'pascal', '^~FILE~\(~LINE~,~POS~\)\s');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 203, 'Borland Delphi', '', 'pascal', '^~FILE~\(~LINE~\)\sE');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 204, 'Free Pascal in Delphi mode', 'dpr', 'pascal', '^~FILE~\(~LINE~,~POS~\)\s');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 205, 'PascalABC', '', 'pascal', '^\[~LINE~,~POS~\]\s~FILE~:');

INSERT INTO default_de (id, code, description, file_ext, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 301, 'Quick Basic 4.5', 'vbscript', 'vb');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 302, 'Free Basic', 'bas', 'vbscript', '^~FILE~\(~LINE~\)\s');

INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 401, 'Java', 'java', 'java', '^~FILE~:~LINE~:\s');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 402, 'Microsoft Visual C#', 'cs', 'csharp', '^~FILE~\(~LINE~,~POS~\):');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 404, 'Go', 'go', 'golang', '^~FILE~:~LINE~:~POS~:');

INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 501, 'Perl', 'pl', 'perl', 'at\s~FILE~\sline\s~LINE~');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 502, 'Python', 'py', 'python', '^\s+File\s"~FILE~",\sline\s~LINE~');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 503, 'Haskell', 'hs', 'haskell', '^~FILE~:~LINE~:~POS~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 504, 'Ruby', 'rb', 'ruby', '');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 505, 'PHP', 'php', 'php', 'in\s~FILE~\son\sline\s~LINE~');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 506, 'Erlang', 'erl', 'erlang', '\/~FILE~:~LINE~:');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 507, 'NodeJS', 'js', 'javascript', '[\\\/]~FILE~:~LINE~');
INSERT INTO default_de (id, code, description, file_ext, syntax, err_regexp)
    VALUES (GEN_ID(key_seq, 1), 509, 'SWI Prolog', 'pro', 'prolog', '^ERROR:\s.+~FILE~:~LINE~:~POS~:');

/* All users are participants here. */
INSERT INTO contests(id, title, ctype, start_date, finish_date) VALUES(101, 'Archive', 1, CURRENT_DATE - 100, CURRENT_DATE + 1000000);
/* Default modules are exported from problems here. */
INSERT INTO contests(id, title, ctype, start_date, finish_date) VALUES(102, 'Default', 0, CURRENT_DATE - 100, CURRENT_DATE + 1000000);

INSERT INTO accounts(id, login, passwd, srole) VALUES(2, 'root', 'root', 0);
INSERT INTO contest_accounts(id, contest_id, account_id, is_jury) VALUES (3, 101, 2, 1);
INSERT INTO contest_accounts(id, contest_id, account_id, is_jury) VALUES (4, 102, 2, 1);

/* Default judge. */
INSERT INTO accounts(id, login, passwd, srole) VALUES(5, 'fox', 'fox', 1);
INSERT INTO judges(id, nick, pin_mode, account_id) VALUES (4, 'fox', 3, 5);

/* See $cats::anonymous_login */
INSERT INTO accounts(id, login, passwd, srole, locked) VALUES(6, 'anonymous', '', 0, 1);

/* See CATS::Globals::contact_* constants. */
INSERT INTO contact_types(id, name, url) VALUES(901, 'Phone', '');
INSERT INTO contact_types(id, name, url) VALUES(902, 'Email', 'mailto:%s');
INSERT INTO contact_types(id, name, url) VALUES(903, 'ICQ', '');
INSERT INTO contact_types(id, name, url) VALUES(904, 'Home page', 'http://%s');
INSERT INTO contact_types(id, name, url) VALUES(905, 'Telegram', 'https://t.me/%s');
