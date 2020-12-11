ALTER TABLE wiki_pages
    ADD CONSTRAINT wiki_pages_name_uniq UNIQUE (name);
