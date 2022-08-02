CREATE ROLE judge;

GRANT SELECT ON TABLE accounts TO judge;
GRANT SELECT ON TABLE contest_accounts TO judge;
GRANT SELECT ON TABLE contest_problems TO judge;
GRANT SELECT ON TABLE contest_sites TO judge;
GRANT SELECT ON TABLE contests TO judge;
GRANT SELECT ON TABLE default_de TO judge;
GRANT SELECT ON TABLE job_sources TO judge;
GRANT SELECT ON TABLE jobs_queue TO judge;
GRANT SELECT ON TABLE jobs TO judge;
GRANT SELECT ON TABLE judge_de_bitmap_cache TO judge;
GRANT SELECT ON TABLE judges TO judge;
GRANT SELECT ON TABLE limits TO judge;
GRANT SELECT ON TABLE logs TO judge;
GRANT SELECT ON TABLE problem_de_bitmap_cache TO judge;
GRANT SELECT ON TABLE problem_sources TO judge;
GRANT SELECT ON TABLE problem_sources_imported TO judge;
GRANT SELECT ON TABLE problem_sources_local TO judge;
GRANT SELECT ON TABLE problems TO judge;
GRANT SELECT ON TABLE req_de_bitmap_cache TO judge;
GRANT SELECT ON TABLE req_details TO judge;
GRANT SELECT ON TABLE req_groups TO judge;
GRANT SELECT ON TABLE reqs TO judge;
GRANT SELECT ON TABLE solution_output TO judge;
GRANT SELECT ON TABLE sources TO judge;
GRANT SELECT ON TABLE tests TO judge;
GRANT SELECT ON TABLE testsets TO judge;

GRANT UPDATE(sid, last_login, last_ip)
    ON TABLE accounts TO judge;

GRANT UPDATE(status)
    ON TABLE contest_problems TO judge;

GRANT DELETE, INSERT
    ON TABLE jobs_queue TO judge;

GRANT UPDATE(state, start_time, finish_time, judge_id)
    ON TABLE jobs TO judge;

GRANT INSERT, UPDATE
    ON TABLE judge_de_bitmap_cache TO judge;

GRANT UPDATE(version, is_alive, alive_date)
    ON TABLE judges TO judge;

GRANT INSERT
    ON TABLE logs TO judge;

GRANT DELETE, INSERT, UPDATE
    ON TABLE problem_de_bitmap_cache TO judge;

GRANT DELETE, INSERT
    ON TABLE req_de_bitmap_cache TO judge;

GRANT DELETE, INSERT
    ON TABLE req_details TO judge;

GRANT UPDATE(state, failed_test, result_time, test_time, judge_id, testsets)
    ON TABLE reqs TO judge;

GRANT INSERT
    ON TABLE solution_output TO judge;

GRANT UPDATE(in_file, in_file_size, in_file_hash, out_file, out_file_size)
    ON TABLE tests TO judge;
