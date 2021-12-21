ALTER TABLE problems DROP CONSTRAINT chk_run_method;

ALTER TABLE problems ADD CONSTRAINT chk_run_method CHECK (run_method IN (0, 1, 2, 3));
