/*--------------------------------------------------------------
**  definitions for CATS
**--------------------------------------------------------------
*/

CREATE TABLE judges (
    id      INTEGER NOT NULL PRIMARY KEY,
    jsid    VARCHAR(30) DEFAULT NULL,
    color   VARCHAR(32),
    nick    VARCHAR(32) NOT NULL,
    lock_counter    INTEGER,
    alive_counter   INTEGER,
    signal  INTEGER DEFAULT NULL,
    accept_contests INTEGER CHECK (accept_contests IN (0, 1)),
    accept_trainings INTEGER CHECK (accept_trainings IN (0, 1))
);


CREATE TABLE default_de (
    id      INTEGER NOT NULL PRIMARY KEY,
    code    INTEGER NOT NULL UNIQUE,
    description VARCHAR(200),
    file_ext    VARCHAR(200),
    in_contests INTEGER DEFAULT 1 CHECK (in_contests IN (0, 1)),
    in_banks    INTEGER DEFAULT 1 CHECK (in_banks IN (0, 1)),
    in_tsess    INTEGER DEFAULT 1 CHECK (in_tsess IN (0, 1))
);


CREATE TABLE accounts (
    id      INTEGER NOT NULL PRIMARY KEY,
    login   VARCHAR(50) NOT NULL UNIQUE,
    passwd  VARCHAR(100) DEFAULT '',    
    sid     VARCHAR(30),
    srole   INTEGER NOT NULL, 
    last_login  TIMESTAMP,
    locked  INTEGER DEFAULT 0 CHECK (locked IN (0, 1)),
    team_name   VARCHAR(200),
    capitan_name VARCHAR(200),    
    country VARCHAR(30),
    motto   VARCHAR(200),
    email   VARCHAR(200),
    home_page   VARCHAR(200),
    icq_number  VARCHAR(200)
);

CREATE TABLE contests (
    id      INTEGER NOT NULL PRIMARY KEY,
    title   VARCHAR(200) NOT NULL,
    start_date  TIMESTAMP,
    finish_date TIMESTAMP,
    freeze_date TIMESTAMP,
    defreeze_date TIMESTAMP,    
    closed  INTEGER DEFAULT 0 CHECK (closed IN (0, 1)),
    history INTEGER DEFAULT 0 CHECK (history IN (0, 1)),
    penalty INTEGER,
    CHECK (start_date <= finish_date AND freeze_date >= start_date AND freeze_date <= finish_date AND defreeze_date >= freeze_date)
);



CREATE TABLE contest_accounts (
    id      INTEGER NOT NULL PRIMARY KEY,
    contest_id  INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,    
    account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    is_admin    INTEGER DEFAULT 0 CHECK (is_admin IN (0, 1)),
    is_jury INTEGER DEFAULT 0 CHECK (is_jury IN (0, 1)),
    is_pop  INTEGER DEFAULT 0 CHECK (is_pop IN (0, 1)),
    is_hidden   INTEGER DEFAULT 0 CHECK (is_hidden IN (0, 1)),
    is_ooc  INTEGER DEFAULT 0 CHECK (is_ooc IN (0, 1)),
    is_remote   INTEGER DEFAULT 0 CHECK (is_remote IN (0, 1)),
    UNIQUE(contest_id, account_id)
);




CREATE TABLE problems (
    id          INTEGER NOT NULL PRIMARY KEY,
    contest_id      INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,
    title       VARCHAR(200) NOT NULL,
    lang        VARCHAR(200) DEFAULT '',
    time_limit      INTEGER DEFAULT 0,
    memory_limit    NUMERIC,
    difficulty      INTEGER DEFAULT 100,
    author      VARCHAR(200) DEFAULT '',
    input_file      VARCHAR(200) NOT NULL,
    output_file     VARCHAR(200) NOT NULL,
    upload_date     TIMESTAMP,
    std_checker     VARCHAR(60),
    statement       BLOB,
    pconstraints    BLOB,
    input_format    BLOB,
    output_format   BLOB,
    zip_archive     BLOB
);


CREATE TABLE contest_problems (
    id      INTEGER NOT NULL PRIMARY KEY,
    problem_id  INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    contest_id  INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,   
    code    CHAR,
    UNIQUE(problem_id, contest_id)
);


CREATE TABLE training_problems (
    id      INTEGER NOT NULL PRIMARY KEY,
    problem_id  INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,   
    UNIQUE(problem_id, account_id)
);


-- stype = 0 - test generator
-- stype = 1 - standart solution
-- stype = 2 - checker
-- stype = 3 - standart solution (используется для проверки набора тестов)


CREATE TABLE problem_sources (
    id      INTEGER NOT NULL PRIMARY KEY,
    stype   INTEGER CHECK (stype IN (0, 1, 2, 3)),
    problem_id  INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    de_id   INTEGER NOT NULL REFERENCES default_de(id) ON DELETE CASCADE,
    src     BLOB,
    fname   VARCHAR(200)
);


CREATE TABLE pictures (
    problem_id  INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    name    VARCHAR(30) NOT NULL,
    extension   VARCHAR(20),
    pic     BLOB
);


CREATE TABLE tests (
    problem_id      INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    rank        INTEGER CHECK (rank > 0),
    generator_id    INTEGER DEFAULT NULL REFERENCES problem_sources(id),
    param       VARCHAR(200) DEFAULT NULL,
    std_solution_id INTEGER DEFAULT NULL REFERENCES problem_sources(id),
    in_file     BLOB,
    out_file        BLOB
);


CREATE TABLE samples (
    problem_id      INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    rank        INTEGER CHECK (rank > 0),
    in_file     BLOB,
    out_file        BLOB
);


CREATE TABLE questions (
    id      INTEGER NOT NULL PRIMARY KEY,
    clarified   INTEGER DEFAULT 0 CHECK (clarified IN (0, 1)),
    submit_time TIMESTAMP,
    clarification_time  TIMESTAMP,    
    question    BLOB,
    answer  BLOB,
    account_id  INTEGER REFERENCES contest_accounts(id) ON DELETE CASCADE,
    received    INTEGER DEFAULT 0 CHECK (received IN (0, 1))
);


CREATE TABLE messages (
    id      INTEGER NOT NULL PRIMARY KEY,
    send_time   TIMESTAMP,
    text    BLOB,
    account_id  INTEGER REFERENCES contest_accounts(id) ON DELETE CASCADE,
    received    INTEGER DEFAULT 0 CHECK (received IN (0, 1))
);


CREATE TABLE reqs (
    id      INTEGER NOT NULL PRIMARY KEY,
    account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    problem_id  INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    contest_id  INTEGER REFERENCES contests(id) ON DELETE CASCADE,
    submit_time TIMESTAMP, /* время отсылки на тестирование */
    test_time   TIMESTAMP, /* время начала тестирования */
    result_time TIMESTAMP, /* время окончания тестирования */
    state   INTEGER,
    result  INTEGER,
    failed_test INTEGER,
    judge_id    INTEGER REFERENCES judges(id) ON DELETE SET NULL, 
    received    INTEGER DEFAULT 0 CHECK (received IN (0, 1))
);

CREATE TABLE log_dumps (
    id      INTEGER NOT NULL PRIMARY KEY,
    dump    BLOB,
    req_id INTEGER REFERENCES reqs(id) ON DELETE CASCADE 
);

CREATE TABLE sources (
    req_id  INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,
    de_id   INTEGER NOT NULL REFERENCES default_de(id) ON DELETE CASCADE,
    src     BLOB,
    fname   VARCHAR(200)        
);

CREATE TABLE contest_photos (
    id          INTEGER NOT NULL PRIMARY KEY,
    contest_id      INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,
    comment     VARCHAR(200),
    photo_preview   BLOB,
    photo       BLOB,
    photo_preview_type  VARCHAR(20),
    photo_type      VARCHAR(20),
    upload_time     TIMESTAMP
);


CREATE GENERATOR key_seq;
CREATE GENERATOR login_seq;

SET GENERATOR key_seq TO 1; 


INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 101, 'Cross-platform C/C++ compiler', 'cpp;c');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 102, 'GNU C++', 'cpp;c;cxx');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 103, 'MS Visual C++', 'cpp;c');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 104, 'Borland C++ 3.1', 'cpp;c');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 201, 'Borland Pascal', 'pas');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 301, 'Quick Basic 4.5', 'bas');
