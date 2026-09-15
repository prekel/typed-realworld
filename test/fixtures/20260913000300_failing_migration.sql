-- migrate:up
CREATE TABLE migration_probe (id INTEGER PRIMARY KEY);
INSERT INTO deliberately_missing_table (id) VALUES (1);

-- migrate:down
DROP TABLE migration_probe;
