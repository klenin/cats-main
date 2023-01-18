CREATE GENERATOR key_seq;
CREATE GENERATOR login_seq;

SET GENERATOR key_seq TO 1000;

CREATE SEQUENCE de_bitmap_cache_seq;
ALTER SEQUENCE de_bitmap_cache_seq RESTART WITH 1000;

CREATE INDEX accounts_sid_idx ON accounts(sid);
CREATE INDEX accounts_name_idx ON accounts(team_name);
CREATE INDEX contest_tags_name_idx ON contest_tags(name);
CREATE INDEX ps_guid_idx ON problem_sources_local(guid);
CREATE INDEX idx_contest_groups_clist ON contest_groups(clist);
CREATE INDEX de_tags_name_idx ON de_tags(name);
CREATE DESCENDING INDEX idx_events_ts ON events(ts);
CREATE DESCENDING INDEX idx_questions_submit_time ON questions(submit_time);
CREATE DESCENDING INDEX idx_reqs_submit_time ON reqs(submit_time);
CREATE DESCENDING INDEX idx_jobs_id ON jobs(id);
