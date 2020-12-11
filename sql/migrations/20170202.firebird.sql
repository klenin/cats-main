CREATE TABLE events (
    id         INTEGER NOT NULL PRIMARY KEY,
    event_type SMALLINT DEFAULT 0 NOT NULL,
    ts         TIMESTAMP NOT NULL,
    account_id INTEGER REFERENCES accounts(id) ON DELETE CASCADE,
    ip         VARCHAR(100) DEFAULT ''
);
CREATE DESCENDING INDEX idx_events_ts ON events(ts);
