CREATE TABLE req_de_bitmap_cache (
    req_id      INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,
    version     INTEGER NOT NULL,
    de_bits1    BIGINT DEFAULT 0,
    de_bits2    BIGINT DEFAULT 0
);

CREATE TABLE problem_de_bitmap_cache (
    problem_id  INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    version     INTEGER NOT NULL,
    de_bits1    BIGINT DEFAULT 0,
    de_bits2    BIGINT DEFAULT 0
);

ALTER TABLE reqs ADD
    elements_count INTEGER DEFAULT 0;

COMMIT;

UPDATE reqs R SET R.elements_count = (SELECT COUNT(*) FROM req_groups RG WHERE RG.group_id = R.id);

CREATE SEQUENCE de_bitmap_cache_seq;

ALTER SEQUENCE de_bitmap_cache_seq RESTART WITH 1000;
