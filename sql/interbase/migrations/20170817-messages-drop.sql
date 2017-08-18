ALTER TABLE messages
  ADD text1 BLOB SUB_TYPE TEXT;
COMMIT;

UPDATE messages SET text1 = text;
COMMIT;

ALTER TABLE messages DROP text;
ALTER TABLE messages ALTER COLUMN text1 TO text;

DROP INDEX idx_messages_send_time;
COMMIT;

ALTER TABLE messages DROP send_time;
COMMIT;

ALTER TABLE messages DROP account_id;
COMMIT;
