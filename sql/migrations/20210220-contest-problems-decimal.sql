ALTER TABLE contest_problems
    ADD scaled_points1   DECIMAL(18, 6);
ALTER TABLE contest_problems
    ADD round_points_to1 DECIMAL(18, 6);
ALTER TABLE contest_problems
    ADD weight1          DECIMAL(18, 6);
COMMIT;

UPDATE contest_problems SET
    scaled_points1   = scaled_points,
    round_points_to1 = round_points_to,
    weight1          = weight;
COMMIT;

ALTER TABLE contest_problems
    DROP     scaled_points;
ALTER TABLE contest_problems
    DROP     round_points_to;
ALTER TABLE contest_problems
    DROP     weight;
COMMIT;

ALTER TABLE contest_problems
    ALTER   scaled_points1    TO scaled_points;
ALTER TABLE contest_problems
    ALTER   round_points_to1  TO round_points_to;
ALTER TABLE contest_problems
    ALTER   weight1            TO weight;
