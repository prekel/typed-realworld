# Changes

## Unreleased

- OpenAPI экспортируется из compiled endpoint graph без запуска сервера;
  `make frontend-types` генерирует клиент из локального документа, а
  `make frontend-types-check` проверяет сохранённый код и входит в `make check`.
- `make server` и `make server-postgres` запускают сервер без сборки фронтенда;
  bundle собирается отдельно командой `make frontend-build`.
- Added the complete RealWorld/Conduit API with SQLite repositories, application
  services, JWT authentication and scrypt password storage.
- Added case-insensitive ASCII user identity constraints and generated schema
  descriptors from dbmate migrations.
- Added pinned official RealWorld Hurl contract tests and `make api-test`.
