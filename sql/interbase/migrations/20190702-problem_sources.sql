CREATE TABLE problem_sources_local (
    id           INTEGER NOT NULL PRIMARY KEY REFERENCES problem_sources(id) ON DELETE CASCADE,
    stype        INTEGER, /* stype: See Constants.pm */
    de_id        INTEGER NOT NULL REFERENCES default_de(id) ON DELETE CASCADE,
    src          BLOB,
    fname        VARCHAR(200),
    name         VARCHAR(60),
    input_file   VARCHAR(200),
    output_file  VARCHAR(200),
    guid         VARCHAR(100), /* For cross-contest references. */
    time_limit   FLOAT, /* In seconds. */
    memory_limit INTEGER, /* In mebibytes. */
    write_limit  INTEGER, /* In bytes */
    main         VARCHAR(200)
);

CREATE TABLE problem_sources_imported (
    id          INTEGER NOT NULL PRIMARY KEY REFERENCES problem_sources(id) ON DELETE CASCADE,
    guid        VARCHAR(100) /* For cross-contest references. */
);

SET TERM ^ ;

CREATE PROCEDURE migrate AS
    DECLARE VARIABLE id_ INTEGER;
    DECLARE VARIABLE old_id INTEGER;
    DECLARE VARIABLE de_id_ INTEGER;
    DECLARE VARIABLE problem_id_ INTEGER;
    DECLARE VARIABLE guid_ VARCHAR(100);
BEGIN
    SELECT id FROM default_de WHERE code = 1 into :de_id_;
    FOR SELECT guid, problem_id FROM problem_sources_import into :guid_, :problem_id_ DO
    BEGIN
        id_ = GEN_ID(key_seq, 1);
        INSERT INTO problem_sources (id, problem_id, de_id) VALUES (:id_, :problem_id_, :de_id_);
        INSERT INTO problem_sources_imported (id, guid) VALUES (:id_, :guid_);

        SELECT id FROM problem_sources WHERE guid = :guid_ into :old_id;

        UPDATE tests SET generator_id = :id_ WHERE generator_id = :old_id AND problem_id = :problem_id_;
        UPDATE tests SET input_validator_id = :id_ WHERE input_validator_id = :old_id AND problem_id = :problem_id_;
        UPDATE tests SET std_solution_id = :id_ WHERE std_solution_id = :old_id AND problem_id = :problem_id_;
    END
END^

SET TERM ; ^

COMMIT;

INSERT INTO problem_sources_local (id, stype, de_id, src, fname, name, 
    input_file, output_file, guid, time_limit, memory_limit, write_limit, main)
SELECT id, stype, de_id, src, fname, name, 
    input_file, output_file, guid, time_limit, memory_limit, write_limit, main
FROM problem_sources ps;

EXECUTE PROCEDURE migrate;

COMMIT;

DROP INDEX ps_guid_idx;
CREATE INDEX ps_guid_idx ON problem_sources_local(guid);

ALTER TABLE problem_sources DROP CONSTRAINT chk_problem_sources_1;

DROP PROCEDURE migrate;

ALTER TABLE problem_sources DROP stype;
ALTER TABLE problem_sources DROP de_id;
ALTER TABLE problem_sources DROP fname;
ALTER TABLE problem_sources DROP name;
ALTER TABLE problem_sources DROP input_file;
ALTER TABLE problem_sources DROP output_file;
ALTER TABLE problem_sources DROP guid;
ALTER TABLE problem_sources DROP time_limit;
ALTER TABLE problem_sources DROP memory_limit;
ALTER TABLE problem_sources DROP write_limit;
ALTER TABLE problem_sources DROP main;

GRANT SELECT ON TABLE problem_sources_imported TO judge;
GRANT SELECT ON TABLE problem_sources_local TO judge;
