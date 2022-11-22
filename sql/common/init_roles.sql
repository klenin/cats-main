CREATE ROLE main;

GRANT ALL ON default_de TO main;
GRANT ALL ON accounts TO main;
GRANT ALL ON account_tokens TO main;
GRANT ALL ON contact_types TO main;
GRANT ALL ON contacts TO main;
GRANT ALL ON judges TO main;
GRANT ALL ON judge_de_bitmap_cache TO main;
GRANT ALL ON contests TO main;
GRANT ALL ON contest_tags TO main;
GRANT ALL ON contest_contest_tags TO main;
GRANT ALL ON topics TO main;
GRANT ALL ON acc_groups TO main;
GRANT ALL ON acc_group_accounts TO main;
GRANT ALL ON acc_group_contests TO main;
GRANT ALL ON sites TO main;
GRANT ALL ON contest_sites TO main;
GRANT ALL ON contest_accounts TO main;
GRANT ALL ON limits TO main;
GRANT ALL ON problems TO main;
GRANT ALL ON problem_de_bitmap_cache TO main;
GRANT ALL ON contest_problems TO main;
GRANT ALL ON contest_problem_des TO main;
GRANT ALL ON problem_sources TO main;
GRANT ALL ON problem_sources_local TO main;
GRANT ALL ON problem_sources_imported TO main;
GRANT ALL ON problem_attachments TO main;
GRANT ALL ON pictures TO main;
GRANT ALL ON tests TO main;
GRANT ALL ON testsets TO main;
GRANT ALL ON samples TO main;
GRANT ALL ON events TO main;
GRANT ALL ON questions TO main;
GRANT ALL ON messages TO main;
GRANT ALL ON reqs TO main;
GRANT ALL ON jobs TO main;
GRANT ALL ON job_sources TO main;
GRANT ALL ON logs TO main;
GRANT ALL ON jobs_queue TO main;
GRANT ALL ON req_de_bitmap_cache TO main;
GRANT ALL ON req_groups TO main;
GRANT ALL ON req_details TO main;
GRANT ALL ON solution_output TO main;
GRANT ALL ON sources TO main;
GRANT ALL ON keywords TO main;
GRANT ALL ON problem_keywords TO main;
GRANT ALL ON contest_groups TO main;
GRANT ALL ON prizes TO main;
GRANT ALL ON awards TO main;
GRANT ALL ON contest_account_awards TO main;
GRANT ALL ON wiki_pages TO main;
GRANT ALL ON wiki_texts TO main;
GRANT ALL ON snippets TO main;
GRANT ALL ON problem_snippets TO main;
GRANT ALL ON jury_view_snippets TO main;
GRANT ALL ON relations TO main;
GRANT ALL ON contest_wikis TO main;
GRANT ALL ON files TO main;
GRANT ALL ON de_tags TO main;
GRANT ALL ON de_de_tags TO main;
GRANT ALL ON contest_de_tags TO main;
GRANT ALL ON proctoring TO main;

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
