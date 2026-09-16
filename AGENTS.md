# Инструкции для агентов

## Область проекта

- `src/domain/` — доменные значения и чистые инварианты RealWorld. Здесь нет
  HTTP, SQL, Lwt и конкретных библиотек аутентификации.
- `src/application/` — application services и порты `Database`, repositories,
  password hashing и token service. Сервис задаёт transaction boundary;
  repository принимает только transaction-scoped `~conn`.
- `src/infrastructure/` — реализации портов через `typed-sql`, Caqti/SQLite,
  scrypt и JWT HS256.
- `src/http/` — DTO, guards и typed-endpoint controllers. DTO задают wire
  shape; доменные типы не сериализуются напрямую.
- `bin/` — composition root Opium: конфигурация, pool, middleware и lifecycle.
- `test/` — unit, integration и wire-contract tests.
- `db/migrations/sqlite/` — источник схемы SQLite, SQL-файлы dbmate. Уже
  применённые миграции не редактируются; PostgreSQL будет отдельным набором.
- `db/schema.json` — снимок, обновляемый только через `make schema`.
  `schema_migrations` в него не включается.
- `tools/schema_snapshot.ml` и `scripts/schema.sh` — introspection временной БД.
  Генерация OCaml выполняется Dune в `_build`; дескрипторы вручную не
  редактируются и не переносятся в domain/application.
- Метаданные пакета задаются в `dune-project`; сгенерированный `.opam` вручную
  не редактируется.

## Направление зависимостей

- controller → application service → repository port;
- infrastructure реализует application ports, но application не импортирует
  infrastructure;
- соединение с БД не покидает callback `Database.with_connection` или
  `Database.transaction`;
- HTTP context может хранить service facade и authenticated user ID, но не
  Caqti connection и не глобальный mutable service locator;
- list repositories возвращают read model целиком, включая автора, following,
  favorited и favorites count. Не собирай одну страницу N+1 запросами.

## Инварианты RealWorld

- Идентификаторы сущностей — разные абстрактные доменные типы (`User.Id`,
  `Article.Id`, `Comment.Id`) поверх положительного `int64`. Преобразование в
  SQL и transport primitives выполняется только на границах.
- Path/query codecs сразу возвращают доменные значения (`User.Username`,
  `Article.Slug`, `Page.Limit`, `Page.Offset`); controller handler не принимает
  промежуточные transport primitives и не валидирует их вручную.
- Для трёх состояний PATCH используй `Domain.Patch` (`Keep`, `Set`, `Clear`),
  а не вложенные `option option`. Недопустимый `null` отклоняй в HTTP DTO до
  вызова application service.
- Runtime routes монтируются через typed-endpoint/Opium; wire-contract закреплён official Hurl suite.
- JSON точно следует официальному RealWorld contract: envelope-поля,
  camelCase, `null` для отсутствующих profile fields и отсутствие `body` в
  элементах списков статей.
- Заголовок авторизации имеет форму `Authorization: Token <jwt>`. Optional auth
  влияет на `following`/`favorited`, но не закрывает публичный endpoint.
- Пароли не хранятся и не логируются в открытом виде. JWT secret и database URL
  поступают через конфигурацию.
- Пользовательские SQL-значения всегда bind parameters typed-sql. Прямой SQL
  разрешён только для версионированной schema migration, pragmas и capability,
  которой ещё нет в typed-sql.
- Изменение username, slug или ownership выполняется атомарно. DELETE/UPDATE
  всегда имеют явный scope, а authorization проверяется внутри той же
  транзакции, что и mutation.
- Ошибки БД классифицируются в infrastructure, application переводит их в
  domain errors, HTTP выбирает статус и безопасный публичный payload.

## Стиль и проверки

- Во всех новых `.ml` и `.mli` используй `open! Base`; к Stdlib обращайся явно.
- Используй `.ocamlformat`, `ppx_let`, `let%bind`/`let%map` для последовательных
  вычислений и immutable data по умолчанию.
- Основной тип модуля называй `t`, сигнатуру `S`, функтор `Make`.
- Публичные контракты и odoc-комментарии размещай в `.mli`.
- SELECT записывай `Query.(from ... |> ... |> select ...)`; `select` ставь
  последним. DML оформляй аналогично через локальное открытие builder.
- Для insert-or-return существующей строки используй target-specific
  `Insert.on_conflict ... |> do_update ... |> returning`. Для идемпотентного
  добавления связи без чтения строки оставляй `on_conflict_do_nothing`.
- Основные команды: `make build`, `make test`, `make fmt`, `make check`.
- Миграции запускаются только явно через `make migrate`. Сервер, сборка и
  получение connection не должны обновлять схему автоматически.
- `make schema-check` не меняет снимок, а показывает расхождение. Проверки
  выполняются на временных SQLite-файлах через тот же dbmate, что и dev-команды.
- Изменение wire contract сопровождай тестом через testing backend или Hurl;
  изменение persistence semantics — SQLite integration test.
- В expect-тестах ставь отдельный `[%expect {| ... |}]` непосредственно после
  каждого `print`/`printf`; не объединяй вывод нескольких печатей в один снимок.
- Markdown пиши на русском, текст в коде и публичных HTTP errors — на английском.
- Не добавляй CI. Не выполняй `git commit`, `git add`, `git init`, push или
  другие изменяющие состояние git-команды, если пользователь явно не попросил
  об этом в текущей задаче.
