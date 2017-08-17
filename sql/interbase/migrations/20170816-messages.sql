ALTER TABLE messages
    ADD contest_id  INTEGER REFERENCES contests(id) ON DELETE CASCADE;
ALTER TABLE messages
    ADD problem_id  INTEGER REFERENCES problems(id) ON DELETE CASCADE;
COMMIT;

INSERT INTO events(id, event_type, ts, account_id)
    SELECT M.id, 3, M.send_time, (SELECT account_id FROM contest_accounts CA WHERE CA.id = M.account_id)
    FROM messages M;

UPDATE messages SET broadcast = 0 WHERE broadcast IS NULL;
UPDATE messages M SET M.contest_id = (SELECT contest_id FROM contest_accounts CA WHERE CA.id = M.account_id);
UPDATE messages M SET M.contest_id = (
    SELECT C.id FROM contests C
    WHERE M.send_time BETWEEN C.start_date AND C.finish_date AND C.is_official = 1)
WHERE M.contest_id IS NULL;
COMMIT;
