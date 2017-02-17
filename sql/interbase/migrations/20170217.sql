CREATE TABLE req_groups (
    group_id    INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,
    element_id  INTEGER NOT NULL REFERENCES reqs(id) ON DELETE CASCADE,
    CONSTRAINT req_groups_pk PRIMARY KEY (group_id, element_id)
);

