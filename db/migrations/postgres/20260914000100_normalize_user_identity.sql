-- migrate:up
CREATE UNIQUE INDEX users_email_lower_unique ON users (lower(email));
CREATE UNIQUE INDEX users_username_lower_unique ON users (lower(username));

-- migrate:down
DROP INDEX users_username_lower_unique;
DROP INDEX users_email_lower_unique;
