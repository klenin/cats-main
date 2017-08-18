ALTER TABLE messages
  ADD text1 BLOB SUB_TYPE TEXT;
COMMIT;

UPDATE messages SET text1 = text;
COMMIT;

ALTER TABLE messages DROP text;
ALTER TABLE messages ALTER COLUMN text1 TO text;
