-- migrate:up
-- Application code stores ASCII identities in lowercase. These expression indexes
-- also protect existing databases against case-only duplicates.
CREATE UNIQUE INDEX users_email_lower_unique ON users(email COLLATE NOCASE);
CREATE UNIQUE INDEX users_username_lower_unique ON users(username COLLATE NOCASE);

-- migrate:down
DROP INDEX users_username_lower_unique;
DROP INDEX users_email_lower_unique;
