user=cats
password=cats
sqlplus=sqlplus

$sqlplus $user/$password << EOF

SET ECHO ON;

DROP TABLE log_dumps;
DROP TABLE sources;
DROP TABLE reqs;
DROP TABLE judges;
DROP TABLE messages;
DROP TABLE contest_problems;
DROP TABLE contest_accounts;
DROP TABLE tsess_problems;
DROP TABLE tests;
DROP TABLE problem_sources;
DROP TABLE pictures;
DROP TABLE samples;
DROP TABLE problems;
DROP TABLE default_de;
DROP TABLE contests;
DROP TABLE tsess;
DROP TABLE accounts;

DROP SEQUENCE key_seq;
DROP SEQUENCE login_seq;

CREATE TABLE judges (
    id		INTEGER NOT NULL PRIMARY KEY,
    jsid	VARCHAR(30) DEFAULT NULL UNIQUE,
    color	VARCHAR(32),
    nick	VARCHAR(32) NOT NULL,
    lock_counter	INTEGER,
    alive_counter	INTEGER,
    signal	INTEGER DEFAULT NULL,
    accept_contests INTEGER CHECK (accept_contests IN (0, 1)),
    accept_banks INTEGER CHECK (accept_banks IN (0, 1)),
    accept_tsess INTEGER CHECK (accept_tsess IN (0, 1))
);


CREATE TABLE default_de (
    id		INTEGER NOT NULL PRIMARY KEY,
    code	INTEGER NOT NULL UNIQUE,
    description	VARCHAR(200),
    file_ext	VARCHAR(200),
    in_contests INTEGER DEFAULT 1 CHECK (in_contests IN (0, 1)),
    in_banks	INTEGER DEFAULT 1 CHECK (in_banks IN (0, 1)),
    in_tsess	INTEGER DEFAULT 1 CHECK (in_tsess IN (0, 1))
);


CREATE TABLE accounts (
    id		INTEGER NOT NULL PRIMARY KEY,
    login	VARCHAR(50) UNIQUE NOT NULL,
    passwd	VARCHAR(100) DEFAULT '',
    sid		VARCHAR(30) UNIQUE,
    srole	INTEGER NOT NULL, -- роль пользователя в системе
    last_login	DATE,
    locked	INTEGER DEFAULT 0 CHECK (locked IN (0, 1)),
    team_name	VARCHAR(200),
    capitan_name VARCHAR(200),    
    country	VARCHAR(30),
    motto	VARCHAR(200),
    email	VARCHAR(200),
    home_page	VARCHAR(200),
    icq_INTEGER	VARCHAR(200)
);


CREATE TABLE contests (
    id		INTEGER NOT NULL PRIMARY KEY,
    title	VARCHAR(200) NOT NULL,
    start_date	DATE,
    finish_date DATE,
    freeze_date DATE,
    defreeze_date DATE,    
    closed	INTEGER DEFAULT 0 CHECK (closed IN (0, 1)),
    history	INTEGER DEFAULT 0 CHECK (history IN (0, 1)),
    penalty	INTEGER,
    CHECK (start_date <= finish_date AND freeze_date >= start_date AND freeze_date <= finish_date AND defreeze_date >= freeze_date)
);


CREATE TABLE tsess (
    id		INTEGER NOT NULL PRIMARY KEY,
    account_id	INTEGER NOT NULL REFERENCES accounts(id),
    title	VARCHAR(60) NOT NULL,
    start_date	DATE
);


CREATE TABLE contest_accounts (
    id		INTEGER PRIMARY KEY,
    contest_id	INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,
    account_id	INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    is_admin	INTEGER DEFAULT 0 CHECK (is_admin IN (0, 1)),
    is_jury	INTEGER DEFAULT 0 CHECK (is_jury IN (0, 1)),
    is_pop	INTEGER DEFAULT 0 CHECK (is_pop IN (0, 1)),
    is_hidden   INTEGER DEFAULT 0 CHECK (is_hidden IN (0, 1)),
    is_ooc	INTEGER DEFAULT 0 CHECK (is_ooc IN (0, 1)),
    is_remote	INTEGER DEFAULT 0 CHECK (is_remote IN (0, 1)),
    UNIQUE(contest_id, account_id)
);



CREATE TABLE problems (
    id			INTEGER PRIMARY KEY,
    contest_id		INTEGER REFERENCES contests(id) ON DELETE CASCADE,
    title		VARCHAR(200) NOT NULL,
    lang		VARCHAR(200) DEFAULT '',
    time_limit		INTEGER DEFAULT 0,
    difficulty		INTEGER DEFAULT 100,
    author		VARCHAR(200) DEFAULT '',
    input_file		VARCHAR(200) NOT NULL,
    output_file		VARCHAR(200) NOT NULL,
    statement		BLOB,
    pconstraints	BLOB,
    input_format	BLOB,
    output_format	BLOB,
    zip_archive		BLOB,
    upload_date		DATE,
    std_checker		VARCHAR(60)
);


CREATE TABLE contest_problems (
    id		INTEGER PRIMARY KEY,
    problem_id	INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    contest_id	INTEGER NOT NULL REFERENCES contests(id) ON DELETE CASCADE,   
    code	CHAR,
    UNIQUE(problem_id, contest_id)
);

CREATE TABLE tsess_problems (
    id		INTEGER PRIMARY KEY,
    problem_id	INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    tsess_id	INTEGER NOT NULL REFERENCES tsess(id) ON DELETE CASCADE,   
    UNIQUE(problem_id, tsess_id)
);


-- stype = 0 - test generator
-- stype = 1 - standart solution
-- stype = 2 - checker
-- stype = 3 - standart solution (используется для проверки набора тестов)


CREATE TABLE problem_sources (
    id		INTEGER PRIMARY KEY,
    stype	INTEGER CHECK (stype IN (0, 1, 2, 3)),
    problem_id	INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    de_id	INTEGER NOT NULL REFERENCES default_de(id) ON DELETE CASCADE,
    src		BLOB,
    fname	VARCHAR(200)
);

CREATE TABLE pictures (
    problem_id	INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    name	VARCHAR(30) NOT NULL,
    extension	VARCHAR(20),
    pic		BLOB
);

CREATE TABLE tests (
    problem_id		INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    rank		INTEGER CHECK (rank > 0),
    generator_id	INTEGER DEFAULT NULL REFERENCES problem_sources(id),
    param		VARCHAR(200) DEFAULT NULL,
    std_solution_id	INTEGER DEFAULT NULL REFERENCES problem_sources(id),
    in_file		BLOB,
    out_file		BLOB
);

CREATE TABLE samples (
    problem_id		INTEGER REFERENCES problems(id) ON DELETE CASCADE,
    rank		INTEGER CHECK (rank > 0),
    in_file		BLOB,
    out_file		BLOB
);


CREATE TABLE messages (
    id		INTEGER NOT NULL PRIMARY KEY,
    message_type	INTEGER NOT NULL, -- CHECK (type IN (0, 1)), -- 0 - бланк вопроса к жюри, 1 - бланк с ответом жюри, 2 - сообщение команде от жюри
    qtime	DATE,
    atime	DATE,    
    que		BLOB,
    ans		BLOB,
    account_id	INTEGER REFERENCES contest_accounts(id) ON DELETE CASCADE,
    received	INTEGER DEFAULT 0 CHECK (received IN (0, 1))
);


CREATE TABLE reqs (
    id		INTEGER NOT NULL PRIMARY KEY,
    account_id	INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    problem_id	INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    contest_id	INTEGER REFERENCES contests(id) ON DELETE CASCADE,
    tsess_id	INTEGER REFERENCES tsess(id) ON DELETE CASCADE,    
    req_type	INTEGER DEFAULT 0,
    submit_time	DATE,
    result_time	DATE,    
    state	INTEGER,
    result	INTEGER,
    failed_test	INTEGER,
    to_judge_id	INTEGER REFERENCES judges(id) ON DELETE SET NULL, -- кому этот запрос был адресован
    judge_id	INTEGER REFERENCES judges(id) ON DELETE SET NULL, -- кем был обработан
    received	INTEGER DEFAULT 0 CHECK (received IN (0, 1))    
);

CREATE TABLE log_dumps (
    id		INTEGER NOT NULL PRIMARY KEY,
    req_id	INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,    
    dump	BLOB,
    judge_id	INTEGER NOT NULL REFERENCES judges(id) ON DELETE CASCADE
);

CREATE TABLE sources (
    req_id	INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,
    de_id	INTEGER NOT NULL REFERENCES default_de(id) ON DELETE CASCADE,
    src		BLOB,
    fname	VARCHAR(200)        
);


CREATE SEQUENCE key_seq START WITH 2;
CREATE SEQUENCE login_seq;

CREATE TRIGGER default_de_on_insert
BEFORE INSERT ON default_de
FOR EACH ROW
BEGIN 
    SELECT key_seq.nextval INTO :new.id FROM dual;
END;
/

INSERT INTO default_de (code, description, file_ext) VALUES (101, 'Cross-platform C/C++ compiler', 'cpp;c');
INSERT INTO default_de (code, description, file_ext) VALUES (102, 'GNU C++', 'cpp;c;cxx');
INSERT INTO default_de (code, description, file_ext) VALUES (103, 'MS Visual C++', 'cpp;c');
INSERT INTO default_de (code, description, file_ext) VALUES (104, 'Borland C++ 3.1', 'cpp;c');
INSERT INTO default_de (code, description, file_ext) VALUES (201, 'Borland Pascal', 'pas');
INSERT INTO default_de (code, description, file_ext) VALUES (301, 'Quick Basic 4.5', 'bas');

DROP TRIGGER default_de_on_insert;

EXIT;
