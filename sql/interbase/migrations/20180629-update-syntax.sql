UPDATE default_de SET syntax = 'c_cpp' WHERE syntax = 'cpp'

UPDATE default_de SET syntax = 'rust' WHERE code = 120;

UPDATE default_de SET syntax = 'pascal' WHERE code = 201;
UPDATE default_de SET syntax = 'pascal' WHERE code = 202;
UPDATE default_de SET syntax = 'pascal' WHERE code = 204;
UPDATE default_de SET syntax = 'pascal' WHERE code = 205;

UPDATE default_de SET syntax = 'vb' WHERE code = 301;
UPDATE default_de SET syntax = 'vb' WHERE code = 302;

UPDATE default_de SET syntax = 'java' WHERE code = 401;
UPDATE default_de SET syntax = 'csharp' WHERE code = 402;
UPDATE default_de SET syntax = 'golang' WHERE code = 404;

UPDATE default_de SET syntax = 'haskell' WHERE code = 503;
UPDATE default_de SET syntax = 'ruby' WHERE code = 504;
UPDATE default_de SET syntax = 'php' WHERE code = 505;

UPDATE default_de SET syntax = 'erlang' WHERE code = 506;
UPDATE default_de SET syntax = 'javascript' WHERE code = 507;
UPDATE default_de SET syntax = 'prolog' WHERE code = 509;

COMMIT;
