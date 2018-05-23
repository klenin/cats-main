GRANT SELECT ON TABLE logs TO judge;
GRANT INSERT ON TABLE logs TO judge;

INSERT INTO jobs (id, req_id, type, state, create_time, start_time, finish_time, judge_id)
SELECT GEN_ID(key_seq, 1), R.id, 1, 2, R.submit_time, R.test_time, R.result_time, R.judge_id
FROM reqs R
WHERE NOT EXISTS (SELECT NULL FROM jobs J WHERE J.req_id = R.id);

INSERT INTO logs (id, dump, job_id)
SELECT GEN_ID(key_seq, 1), LD.dump, (SELECT J.id FROM jobs J WHERE J.req_id = LD.req_id ORDER BY J.id DESC ROWS 1)
FROM log_dumps LD;

DROP TABLE log_dumps;
