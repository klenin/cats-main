ALTER TABLE contest_problems
    DROP CONSTRAINT chk_contest_problems_st;
COMMIT;

UPDATE contest_problems SET status = 6 WHERE status = 5;
COMMIT;

ALTER TABLE contest_problems
    ADD CONSTRAINT chk_contest_problems_st CHECK (0 <= status AND status <= 6);
COMMIT;
