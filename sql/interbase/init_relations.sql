/*--------------------------------------------------------------
**  definitions for CATS
**--------------------------------------------------------------
*/

CREATE TABLE judges (
    id      INTEGER NOT NULL PRIMARY KEY,
    jsid    VARCHAR(30) DEFAULT NULL,
    nick    VARCHAR(32) NOT NULL,
    lock_counter     INTEGER,
    is_alive         INTEGER DEFAULT 0 CHECK (is_alive IN (0, 1)),
    alive_date       TIMESTAMP
);


CREATE TABLE default_de (
    id          INTEGER NOT NULL PRIMARY KEY,
    code        INTEGER NOT NULL UNIQUE,
    description VARCHAR(200),
    file_ext    VARCHAR(200),
    in_contests INTEGER DEFAULT 1 CHECK (in_contests IN (0, 1)),
    in_banks    INTEGER DEFAULT 1 CHECK (in_banks IN (0, 1)),
    in_tsess    INTEGER DEFAULT 1 CHECK (in_tsess IN (0, 1)),
    memory_handicap INTEGER DEFAULT 0,
    syntax      VARCHAR(200) /* ��� highilghter'� */
);


CREATE TABLE accounts (
    id      INTEGER NOT NULL PRIMARY KEY,
    login   VARCHAR(50) NOT NULL UNIQUE,
    passwd  VARCHAR(100) DEFAULT '',    
    sid     VARCHAR(30),
    srole   INTEGER NOT NULL, /* 0 - root, 1 - user, 2 - can create contests */
    last_login  TIMESTAMP,
    last_ip     VARCHAR(100) DEFAULT '',
    locked      INTEGER DEFAULT 0 CHECK (locked IN (0, 1)),
    team_name   VARCHAR(200),
    capitan_name VARCHAR(200),    
    country     VARCHAR(30),
    motto       VARCHAR(200),
    email       VARCHAR(200),
    home_page   VARCHAR(200),
    icq_number  VARCHAR(200),
    settings    BLOB SUB_TYPE 0,
    city        VARCHAR(200)
);
CREATE INDEX accounts_sid_idx ON accounts(sid);

CREATE TABLE contests (
    id            INTEGER NOT NULL PRIMARY KEY,
    title         VARCHAR(200) NOT NULL,
    start_date    TIMESTAMP,
    finish_date   TIMESTAMP,
    freeze_date   TIMESTAMP,
    defreeze_date TIMESTAMP,    
    closed        INTEGER DEFAULT 0 CHECK (closed IN (0, 1)),
    is_hidden     SMALLINT DEFAULT 0 CHECK (is_hidden IN (0, 1)),
    penalty       INTEGER,
    ctype         INTEGER, /* 0 -- normal, 1 -- training session */

    is_official   INTEGER DEFAULT 0 CHECK (is_official IN (0, 1)),
    run_all_tests INTEGER DEFAULT 0 CHECK (run_all_tests IN (0, 1)),

    show_all_tests       INTEGER DEFAULT 0 CHECK (show_all_tests IN (0, 1)),
    show_test_resources  INTEGER DEFAULT 0 CHECK (show_test_resources IN (0, 1)),
    show_checker_comment INTEGER DEFAULT 0 CHECK (show_checker_comment IN (0, 1)),
    show_packages        INTEGER DEFAULT 0 CHECK (show_packages IN (0, 1)),
    show_all_results     SMALLINT DEFAULT 1 NOT NULL CHECK (show_all_results IN (0, 1)),
    rules                INTEGER DEFAULT 0, /* �������: 0 - ACM, 1 - �������� */
    local_only           SMALLINT DEFAULT 0 CHECK (local_only IN (0, 1)),
    /* �������� ������� �� ����� ������ �� ������ ��������� */
    max_reqs             INTEGER DEFAULT 0,
    /* TODO: �������� ������� � ������������ ������� */
    show_frozen_reqs     SMALLINT DEFAULT 0 CHECK (show_frozen_reqs IN (0, 1)),

    CHECK (
        start_date <= finish_date AND freeze_date >= start_date
        AND freeze_date <= finish_date AND defreeze_date >= freeze_date
    )
);


CREATE TABLE contest_accounts (
    id          INTEGER NOT NULL PRIMARY KEY,
    contest_id  INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,    
    account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    is_admin    INTEGER DEFAULT 0 CHECK (is_admin IN (0, 1)),
    is_jury     INTEGER DEFAULT 0 CHECK (is_jury IN (0, 1)),
    is_pop      INTEGER DEFAULT 0 CHECK (is_pop IN (0, 1)), /* printer operator */
    is_hidden   INTEGER DEFAULT 0 CHECK (is_hidden IN (0, 1)),
    is_ooc      INTEGER DEFAULT 0 CHECK (is_ooc IN (0, 1)),
    is_remote   INTEGER DEFAULT 0 CHECK (is_remote IN (0, 1)),
    tag         VARCHAR(200),
    is_virtual  INTEGER,
    diff_time   FLOAT,
    UNIQUE(contest_id, account_id)
);


CREATE TABLE problems (
    id              INTEGER NOT NULL PRIMARY KEY,
    contest_id      INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,
    title           VARCHAR(200) NOT NULL,
    lang            VARCHAR(200) DEFAULT '',
    time_limit      INTEGER DEFAULT 0,
    memory_limit    INTEGER,
    difficulty      INTEGER DEFAULT 100,
    author          VARCHAR(200) DEFAULT '',
    repo_id         VARCHAR(100) DEFAULT '',
    commit_sha      VARCHAR(100) DEFAULT '',
    input_file      VARCHAR(200) NOT NULL,
    output_file     VARCHAR(200) NOT NULL,
    upload_date     TIMESTAMP,
    std_checker     VARCHAR(60),
    statement       BLOB,
    explanation     BLOB,
    pconstraints    BLOB,
    input_format    BLOB,
    output_format   BLOB,
    formal_input    BLOB,
    json_data       BLOB,
    zip_archive     BLOB,
    last_modified_by INTEGER REFERENCES accounts(id) ON DELETE SET NULL ON UPDATE CASCADE,
    max_points      INTEGER,
    hash            VARCHAR(200)
);


CREATE TABLE contest_problems (
    id              INTEGER NOT NULL PRIMARY KEY,
    problem_id      INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    contest_id      INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,   
    code            CHAR,
    status          INTEGER DEFAULT 0 CHECK (status IN (0, 1, 2, 3)),
    testsets        VARCHAR(200),
    points_testsets VARCHAR(200),
    max_points      INTEGER,
    UNIQUE (problem_id, contest_id)
);


-- stype = 0 - test generator
-- stype = 1 - solution
-- stype = 2 - checker
-- stype = 3 - standart solution (������������ ��� �������� ������ ������)

CREATE TABLE problem_sources (
    id          INTEGER NOT NULL PRIMARY KEY,
    stype       INTEGER,
    problem_id  INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    de_id       INTEGER NOT NULL REFERENCES default_de(id) ON DELETE CASCADE,
    src         BLOB,
    fname       VARCHAR(200),
    input_file  VARCHAR(200),
    output_file VARCHAR(200),
    guid        VARCHAR(100), /* ���������� ������������� ��������� */
    time_limit  FLOAT, /* � �������� */
    memory_limit INTEGER /* � ���������� */
);
ALTER TABLE problem_sources
  ADD CONSTRAINT chk_problem_sources_1 CHECK (0 <= stype AND stype <= 6);
CREATE INDEX ps_guid_idx ON problem_sources(guid);

CREATE TABLE problem_sources_import
(
    problem_id  INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    /* ������ �� problem_sources.guid, constraint ����������, ����� ��������� ���������� �������� ������ */
    guid        VARCHAR(100) NOT NULL,
    PRIMARY KEY (problem_id, guid)
);


CREATE TABLE problem_attachments (
    id          INTEGER NOT NULL PRIMARY KEY,
    problem_id  INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    name        VARCHAR(200) NOT NULL,
    file_name   VARCHAR(200) NOT NULL,
    data        BLOB
);


CREATE TABLE pictures (
    id          INTEGER NOT NULL PRIMARY KEY,
    problem_id  INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    name        VARCHAR(30) NOT NULL,
    extension   VARCHAR(20),
    pic         BLOB
);


CREATE TABLE tests (
    problem_id      INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    rank            INTEGER CHECK (rank > 0),
    generator_id    INTEGER DEFAULT NULL REFERENCES problem_sources(id) ON DELETE CASCADE,
    param           VARCHAR(200) DEFAULT NULL,
    std_solution_id INTEGER DEFAULT NULL REFERENCES problem_sources(id) ON DELETE CASCADE,
    in_file         BLOB,
    out_file        BLOB,
    points          INTEGER,
    gen_group       INTEGER
);


CREATE TABLE testsets
(
    id              INTEGER NOT NULL,
    problem_id      INTEGER NOT NULL,
    name            VARCHAR(200) NOT NULL,
    tests           VARCHAR(200) NOT NULL,
    points          INTEGER,
    comment         VARCHAR(400),
    CONSTRAINT testsets_pk PRIMARY KEY (id),
    /*CONSTRAINT testsets_uniq UNIQUE (name, problem_id),*/
    FOREIGN KEY (problem_id) REFERENCES problems (id) ON DELETE CASCADE
);


CREATE TABLE samples (
    problem_id      INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    rank            INTEGER CHECK (rank > 0),
    in_file         BLOB,
    out_file        BLOB
);


CREATE TABLE questions (
    id          INTEGER NOT NULL PRIMARY KEY,
    clarified   INTEGER DEFAULT 0 CHECK (clarified IN (0, 1)),
    submit_time TIMESTAMP,
    clarification_time  TIMESTAMP,    
    question    BLOB,
    answer      BLOB,
    account_id  INTEGER REFERENCES contest_accounts(id) ON DELETE CASCADE,
    received    INTEGER DEFAULT 0 CHECK (received IN (0, 1))
);
CREATE DESCENDING INDEX idx_questions_submit_time ON questions(submit_time);


CREATE TABLE messages (
    id          INTEGER NOT NULL PRIMARY KEY,
    send_time   TIMESTAMP,
    text        BLOB,
    account_id  INTEGER REFERENCES contest_accounts(id) ON DELETE CASCADE,
    received    INTEGER DEFAULT 0 CHECK (received IN (0, 1)),
    broadcast   INTEGER DEFAULT 0 CHECK (broadcast IN (0, 1))
);
CREATE DESCENDING INDEX idx_messages_send_time ON messages(send_time);


CREATE TABLE reqs (
    id          INTEGER NOT NULL PRIMARY KEY,
    account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    problem_id  INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    contest_id  INTEGER REFERENCES contests(id) ON DELETE CASCADE,
    submit_time TIMESTAMP, /* ����� ������� �� ������������ */
    test_time   TIMESTAMP, /* ����� ������ ������������ */
    result_time TIMESTAMP, /* ����� ��������� ������������ */
    state       INTEGER,
    failed_test INTEGER,
    judge_id    INTEGER REFERENCES judges(id) ON DELETE SET NULL, 
    received    INTEGER DEFAULT 0 CHECK (received IN (0, 1)),
    points      INTEGER,
    testsets    VARCHAR(200)
);
CREATE DESCENDING INDEX idx_reqs_submit_time ON reqs(submit_time);


CREATE TABLE req_details
(
  req_id            INTEGER NOT NULL REFERENCES REQS(ID) ON DELETE CASCADE,
  test_rank         INTEGER NOT NULL /*REFERENCES TESTS(RANK) ON DELETE CASCADE*/,
  result            INTEGER,
  time_used         FLOAT,
  memory_used       INTEGER,
  disk_used         INTEGER,
  checker_comment   VARCHAR(400),
  
  UNIQUE(req_id, test_rank)
);


CREATE TABLE log_dumps (
    id      INTEGER NOT NULL PRIMARY KEY,
    dump    BLOB,
    req_id  INTEGER REFERENCES reqs(id) ON DELETE CASCADE 
);


CREATE TABLE sources (
    req_id  INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,
    de_id   INTEGER NOT NULL REFERENCES default_de(id) ON DELETE CASCADE,
    src     BLOB,
    fname   VARCHAR(200),
    hash    CHAR(32) /* md5_hex */
);


CREATE TABLE keywords (
    id          INTEGER NOT NULL PRIMARY KEY,
    name_ru     VARCHAR(200),
    name_en     VARCHAR(200),
    code        VARCHAR(200)
);


CREATE TABLE problem_keywords (
    problem_id  INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    keyword_id  INTEGER NOT NULL REFERENCES keywords(id) ON DELETE CASCADE,
    PRIMARY KEY (problem_id, keyword_id)
);


CREATE TABLE contest_groups (
    id     INTEGER NOT NULL PRIMARY KEY,
    name   VARCHAR(200) NOT NULL,
    /* Comma-separated sorted list of contest ids. */
    clist  VARCHAR(200)
);
CREATE INDEX idx_contest_groups_clist ON contest_groups(clist);


CREATE TABLE prizes (
    id     INTEGER NOT NULL PRIMARY KEY,
    cg_id  INTEGER NOT NULL REFERENCES contest_groups(id) ON DELETE CASCADE,
    name   VARCHAR(200) NOT NULL,
    rank   INTEGER NOT NULL
);


/*
    ������ ������ Firebird �� ����� ������ CAST � BLOB,
    ������� ������ ����������� ������ ����� ���������� ������
    select ����� ���� BLOB �� dummy_table.
*/
CREATE TABLE dummy_table
(
    t_integer INTEGER,
    t_varchar200 VARCHAR(200),
    t_blob BLOB SUB_TYPE 0
);


CREATE GENERATOR key_seq;
CREATE GENERATOR login_seq;

SET GENERATOR key_seq TO 1000;


INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 101, 'Cross-platform C/C++ compiler', 'cpp;c');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 102, 'GNU C++', 'cpp;c;cxx');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 103, 'MS Visual C++', 'cpp;c');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 104, 'Borland C++ 3.1', 'cpp;c');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 201, 'Borland Pascal', 'pas');
INSERT INTO default_de (id, code, description, file_ext) VALUES (GEN_ID(key_seq, 1), 301, 'Quick Basic 4.5', 'bas');

INSERT INTO dummy_table VALUES (NULL, NULL, NULL);
