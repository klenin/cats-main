ALTER TABLE problem_sources
  DROP CONSTRAINT chk_problem_sources_1;
ALTER TABLE problem_sources
  ADD CONSTRAINT chk_problem_sources_1 CHECK (0 <= stype AND stype <= 15);
ALTER TABLE req_details
  ADD points INTEGER;
