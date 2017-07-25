CREATE TABLE judge_de_bitmap_cache (
    judge_id    INTEGER NOT NULL UNIQUE REFERENCES judges(id) ON DELETE CASCADE,
    version     INTEGER NOT NULL,
    de_bits1    BIGINT DEFAULT 0,
    de_bits2    BIGINT DEFAULT 0
);

