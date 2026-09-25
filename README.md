# typed-realworld

Backend полной спецификации RealWorld/Conduit на OCaml 5.5. API работает под
`/api`, использует Opium и runtime adapter `typed-endpoint`; persistence
реализован через Caqti/SQLite и generated descriptors `typed-sql`.

Текущие направления развития описаны в [дорожной карте](doc/roadmap.md).

Поддержаны регистрация и login, current user, profiles/follow, публикация,
лента, фильтрация и pagination статей, теги, favorites и comments. Точный
wire-contract проверяется закреплённым официальным набором Hurl.

Сгенерированная OpenAPI 3.1 спецификация доступна по `/openapi.json`. Страница
`/docs` ведёт на Swagger UI, Scalar, RapiDoc, Redoc и Stoplight Elements; все
рендереры читают один и тот же runtime-документ.

## Быстрый старт

Нужны opam, Node.js 22.18 или новее, SQLite development headers и чистые worktree
`../typed-endpoint-v0.1.1` и `../typed-sql-v0.3.2`. Их можно создать
командами `git -C ../typed-endpoint worktree add --detach ../typed-endpoint-v0.1.1 v0.1.1`
и `git -C ../typed-sql worktree add --detach ../typed-sql-v0.3.2 v0.3.2`.

```sh
make create_switch
make deps_all
make tools
make migrate
make server
```

Сервер по умолчанию слушает `http://127.0.0.1:3000`: на `/` и `/app` он
отдаёт HTML shell, `/app.js` — настроенный JS bundle, а `/api` — API. Для bundle
`make server` сначала собирает React/TypeScript frontend. Bundle можно задать
через `REALWORLD_FRONTEND_BUNDLE`; без доступного файла `/app.js` вернёт 503.
Для обновления сгенерированного API-клиента оставь backend запущенным и выполни
`make frontend-types` в другом терминале. Сервер не применяет миграции самостоятельно.

| Переменная | Значение по умолчанию |
| --- | --- |
| `REALWORLD_DATABASE_URL` | `sqlite3:realworld.sqlite3` |
| `REALWORLD_PORT` | `3000` |
| `REALWORLD_JWT_SECRET` | development secret с предупреждением в stderr |
| `REALWORLD_FRONTEND_BUNDLE` | `frontend/dist/frontend.bundle.js` |

Для production обязательно задать `REALWORLD_JWT_SECRET`. JWT используют HS256
и действуют 24 часа. `Authorization` имеет вид `Token <jwt>`.

## Миграции и схема

```sh
make migration NAME=add_index
make schema
make schema-check
REALWORLD_DATABASE_URL=sqlite3:/tmp/realworld.sqlite3 make migrate
```

SQL-миграции в `db/migrations/sqlite/` — источник структуры. `make schema`
строит временную БД и обновляет `db/schema.json`; Dune генерирует descriptors
только в `_build`. Уже применённые миграции не редактируются.

Email и username принимаются в ASCII, нормализуются к нижнему регистру и
защищены SQLite `NOCASE` unique indexes. Конфликт slug разрешается как
`title`, `title-2`, `title-3`.

## Проверки

```sh
make test       # unit и миграционные SQLite integration tests
make frontend-test # React component и generated-client tests
make api-test   # временная БД, сервер, official RealWorld и project Hurl scenarios
make check      # fmt, build, tests, Hurl, docs, package и schema check
```

`make frontend-build` запускает TypeScript typecheck и собирает bundle; `make
server` и `make api-test` также собирают frontend bundle.

Официальные Hurl-сценарии сохранены в `test/hurl/official/`; их upstream
revision указан в `UPSTREAM`. Дополнительные regression-сценарии проекта лежат
в `test/hurl/project/`. `make hurl-tools` загружает Hurl 8.0.1 в `.tools/bin`
с SHA-256 проверкой.

## Структура

- `src/domain` — значения и инварианты.
- `src/application/*_service.ml` — use cases и transaction boundaries;
  `*_repository.mli` — порты persistence.
- `src/infrastructure/sqlite/*_queries.ml` — корневые statements `typed-sql`;
  отдельный модуль рядом со statement используется только для record input из
  нескольких полей. `Statement.Dynamic` применяется для batch-запросов с
  переменным числом значений `IN`; `*_repository_sqlite.ml` —
  SQLite-адаптеры application-портов; `database_sqlite_lwt.ml` — pool и
  транзакции. Lookup statements используют `LIMIT 1` и статическую
  cardinality-модель, а `RETURNING` с business invariant явно проверяется
  через `expect_one`.
- `src/infrastructure/security` — scrypt и JWT HS256.
- `src/http/*_controller.ml` — typed-endpoint DSL, DTO, точные JSON Schema и
  auth context; `app.ml` компилирует группы endpoint и монтирует сгенерированный
  OpenAPI вместе со страницами документации.
- `bin` — конфигурация, wiring service/repository, pool и lifecycle.
