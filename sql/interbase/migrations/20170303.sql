ALTER TABLE judges ADD
    pin_mode INTEGER DEFAULT 0;
ALTER TABLE judges ADD CONSTRAINT chk_judge_pin_mode
  CHECK (pin_mode IN (0, 1, 2, 3));
ALTER TABLE judges ALTER pin_mode POSITION 4;
COMMIT;
UPDATE judges SET pin_mode = (1 - lock_counter) * 3;
COMMIT;
ALTER TABLE judges DROP lock_counter;
