CREATE TABLE resources (
    id          INTEGER NOT NULL PRIMARY KEY,
    res_type    INTEGER NOT NULL, /* 1 -- git */
    url         VARCHAR(200) NOT NULL,
    CONSTRAINT resources_url_uniq UNIQUE(url)
);

CREATE TABLE problem_resources (
    id          INTEGER NOT NULL PRIMARY KEY,
    problem_id  INTEGER NOT NULL,
    resource_id INTEGER NOT NULL,
    name        VARCHAR(200) NOT NULL,
    CONSTRAINT problem_resources_pr_id_fk
        FOREIGN KEY (problem_id) REFERENCES problems(id) ON DELETE CASCADE,
    CONSTRAINT problem_resources_res_id_fk
        FOREIGN KEY (resource_id) REFERENCES resources(id)
);

CREATE TABLE problem_source_resources (
    problem_resource_id INTEGER,
    problem_source_id   INTEGER,
    CONSTRAINT problem_source_res_res_id_fk
        FOREIGN KEY (problem_resource_id) REFERENCES problem_resources(id) ON DELETE CASCADE,
    CONSTRAINT problem_source_res_ps_id_fk
        FOREIGN KEY (problem_source_id) REFERENCES problem_sources_local(id) ON DELETE CASCADE
);
