ALTER TABLE problems
    DROP CONSTRAINT chk_run_method;

ALTER TABLE problems ADD CONSTRAINT chk_run_method CHECK (run_method >= 0);
