# typed-realworld

Backend полной спецификации RealWorld/Conduit на OCaml 5.5. API работает под
`/api`, использует Opium и runtime adapter `typed-endpoint`; persistence
реализован через Caqti/SQLite и generated descriptors `typed-sql`.
Минимальный браузерный клиент на Bonsai и js_of_ocaml доступен на `/`.

Текущие направления развития описаны в [дорожной карте](doc/roadmap.md).

Поддержаны регистрация и login, current user, profiles/follow, публикация,
лента, фильтрация и pagination статей, теги, favorites и comments. Точный
wire-contract проверяется закреплённым официальным набором Hurl.

Сгенерированная OpenAPI 3.1 спецификация доступна по `/openapi.json`. Страница
`/docs` ведёт на Swagger UI, Scalar, RapiDoc, Redoc и Stoplight Elements; все
рендереры читают один и тот же runtime-документ.

## Быстрый старт

Нужны opam, SQLite development headers и чистые worktree
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
отдаёт клиент, на `/api` — API. Backend использует локальный switch OCaml
5.5.1, frontend — отдельный switch Bonsai на OCaml 5.1.1. Для frontend выполни
`opam switch create frontend 5.1.1 -y` и `make frontend-deps`. `make server`
собирает JS в frontend switch и запускает сервер из backend switch. Клиент показывает статьи, позволяет
зарегистрироваться, войти и опубликовать статью. Токен хранится только в памяти
страницы. Сервер не применяет миграции самостоятельно.

| Переменная | Значение по умолчанию |
| --- | --- |
| `REALWORLD_DATABASE_URL` | `sqlite3:realworld.sqlite3` |
| `REALWORLD_PORT` | `3000` |
| `REALWORLD_JWT_SECRET` | development secret с предупреждением в stderr |
| `REALWORLD_FRONTEND_BUNDLE` | `frontend/_build/default/main.bc.js` |

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
make api-test   # временная БД, сервер, official RealWorld и project Hurl scenarios
make check      # fmt, build, tests, Hurl, docs, package и schema check
```

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
