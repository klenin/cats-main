INSERT INTO contact_types(id, name, url) VALUES(901, 'Phone', '');
INSERT INTO contact_types(id, name, url) VALUES(902, 'Email', 'mailto:%s');
INSERT INTO contact_types(id, name, url) VALUES(903, 'ICQ', '');
INSERT INTO contact_types(id, name, url) VALUES(904, 'Home page', 'http://%s');
INSERT INTO contact_types(id, name, url) VALUES(905, 'Telegram', 'https://t.me/%s');

INSERT INTO contacts(id, account_id, contact_type_id, handle, is_public, is_actual)
    SELECT GEN_ID(key_seq, 1), id, 901, phone, 0, 1 FROM accounts WHERE phone IS NOT NULL AND phone <> '';
INSERT INTO contacts(id, account_id, contact_type_id, handle, is_public, is_actual)
    SELECT GEN_ID(key_seq, 1), id, 902, email, 1, 0 FROM accounts WHERE email IS NOT NULL AND email <> '';
INSERT INTO contacts(id, account_id, contact_type_id, handle, is_public, is_actual)
    SELECT GEN_ID(key_seq, 1), id, 903, icq_number, 0, 0 FROM accounts WHERE icq_number IS NOT NULL AND icq_number <> '';
INSERT INTO contacts(id, account_id, contact_type_id, handle, is_public, is_actual)
    SELECT GEN_ID(key_seq, 1), id, 904, home_page, 1, 0 FROM accounts WHERE home_page IS NOT NULL AND home_page <> '';

COMMIT;
