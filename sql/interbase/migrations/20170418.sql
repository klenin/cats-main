ALTER TABLE contest_problems DROP CONSTRAINT chk_contest_problems_st;
ALTER TABLE contest_problems ADD CONSTRAINT chk_contest_problems_st CHECK (0 <= status AND status <= 5);

UPDATE contest_problems cp SET cp.status = cp.status + 1 WHERE cp.status > 1;
