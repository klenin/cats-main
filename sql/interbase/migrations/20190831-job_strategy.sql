UPDATE limits SET job_split_strategy = NULL
WHERE job_split_strategy NOT IN ('none', 'subtasks');

UPDATE limits SET job_split_strategy = '{"method": "' || job_split_strategy || '"}';

COMMIT;
