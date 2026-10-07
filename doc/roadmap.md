# Дорожная карта

## Текущее состояние

Приложение реализует полный HTTP-контракт RealWorld: регистрацию и login,
current user, profiles и follows, articles, feed, tags, favorites и comments.
Контроллеры собраны через `typed-endpoint`, application services задают
transaction boundaries, repositories используют `typed-sql`, а схема
изменяется только версионированными dbmate migrations.

Для SQLite и PostgreSQL есть отдельные реализации подключения, миграции и
серверные бинарники. React/TypeScript frontend использует клиент, сгенерированный
из OpenAPI. `make check` проверяет форматирование, сборку, тесты, Hurl suite,
документацию, opam package и соответствие `db/schema.json` SQLite-миграциям.

Этапы ниже не расширяют RealWorld wire contract. Они описывают устранение полных
сканов, усиление persistence invariants, сокращение числа и объёма запросов и
укрепление внутренних границ.

## Возможности текущего typed-sql

В `typed-sql 0.4.5` доступны необходимые возможности:

- `JOIN`, correlated `EXISTS`, aggregates, scalar subqueries и applicative
  projections для read models;
- nullable parameters и `Query.where_optional_param` для одного статического
  SQL shape;
- `WHERE` в `UPDATE`/`DELETE`, `RETURNING`, `expect_optional` и
  `expect_one` для scoped mutations;
- target-specific `ON CONFLICT`, `DO UPDATE` и `DO NOTHING`;
- `Statement.Dynamic` для batch `IN`, где число идентификаторов действительно
  меняет SQL shape;
- `Statement.with_parameters` для статических statements с общим input и
  аппликативно собранными typed bind-параметрами;
- `Statement.choose_dialect` для batch lookup пользователей: PostgreSQL
  использует `= ANY` с одним параметром `bigint[]`, SQLite — `IN` с отдельным
  bind-параметром на каждый ID;
- `Query.exists_expr` для boolean projection без nullable scalar subquery;
- типизированный `Values` как источник строк для `FROM` и `JOIN`;
- `Insert.from_select` для вставки результата совместимого `SELECT`;
- структурированная классификация constraint violations в Caqti adapter.

`Query.aggregate_one` даёт proof для ungrouped aggregate на уровне типов. Count
statement статей использует этот combinator. Article read model применяет
`Query.exists_expr` для `following` и `favorited`, получая ненулевые SQL
boolean-значения. Правила для aggregate и query statements зафиксированы в
`AGENTS.md`. Инструмент снимка схемы теперь использует отдельные пакеты
`typed-sql-schema` и `typed-sql-schema-caqti-lwt`; порядок обновления схемы
описан в [руководстве по миграциям](migrations.md).

## 1. Убрать полные сканы profiles и follows

- [x] Этап выполнен.

Раньше получение одного профиля читало все строки `users` и `follows`.
`follow` и `unfollow` после изменения связи снова читали всю таблицу follows,
чтобы построить один response.

Реализовано:

- [x] Добавить `profile_by_username`, выбирающий одного пользователя;
- [x] Вычислять `following` через correlated `EXISTS` только для текущего viewer;
- [x] После успешного `follow` строить response с `following = true`, после
  `unfollow` — с `following = false`, не перечитывая все связи;
- [x] Удалить `User_queries.all_rows`, `User_queries.all_follows` и ставшие
  ненужными helpers из `repository_support.ml`;
- [x] Сохранить корректное поведение optional auth: без viewer поле `following`
  равно `false`.

Готово, когда profile/follow/unfollow не содержат запросов без ограничения по
username, user ID или конкретной паре follower/followed, а SQLite integration
tests проверяют оба значения `following`.

## 2. Включить ownership в mutation SQL

- [x] Этап выполнен.

Проверка владельца и mutation выполняются в одной транзакции. Mutation также
повторяет authorization invariant в своём `WHERE`.

Реализовано:

- [x] Обновлять статью с `WHERE article.id = ? AND article.author_id = ?`;
- [x] Удалять статью с тем же ownership scope;
- [x] Удалять комментарий с ограничением по comment ID, article ID и author ID;
- [x] Использовать `RETURNING` и `expect_optional`, чтобы отличать выполненный
  mutation от исчезнувшей или изменившейся строки;
- [x] Сохранить предварительный lookup только там, где он нужен для различения
  `Not_found` и `Forbidden`;
- [x] Проверить rollback всей операции, включая изменения тегов.

Готово, когда ни один ownership-sensitive mutation нельзя выполнить SQL-запросом
только по публичному идентификатору и integration tests проверяют чужого
владельца и удалённую между lookup и mutation строку.

## 3. Сохранить структурированные persistence errors

- [x] Этап выполнен.

Раньше `Repository_support.run` сразу превращал adapter error в строковый
`Persistence_error`, а создание статьи распознавало конфликт slug поиском слова
`constraint`. Это смешивало unique, foreign-key и check violations и плохо
работало при конкурентных запросах.

Реализовано:

- [x] Классифицировать `Typed_sql_caqti_lwt.Constraint_violation` до преобразования
  в публичный `Persistence_error`;
- [x] Для статьи переводить только unique violation операции записи slug в
  `Slug_taken`;
- [x] После unique conflict пользователя перечитывать email и username и
  определять `Email_taken`/`Username_taken` по данным, не по тексту сообщения
  драйвера;
- [x] Одинаково обрабатывать conflict при create и update;
- [x] Не возвращать внутреннее сообщение БД через HTTP;
- [x] Добавить integration tests для case-insensitive конфликтов и конфликтов,
  возникающих после предварительного lookup.

Для этого не требуется более детальная ошибка от `typed-sql`: текущего
constraint kind достаточно, а конкретный business conflict можно установить
повторным typed lookup внутри той же transaction boundary.

## 4. Сократить article read model

- [x] Этап выполнен.

Раньше страница статей после основного SELECT отдельно загружала авторов,
подписки, tags, article-tags и все favorite rows выбранных статей. Это не N+1,
но объём favorites растёт вместе с полной популярностью статьи, а не с размером
страницы.

Реализовано:

- [x] Присоединять автора к основному article query;
- [x] Вычислять `following` и `favorited` через correlated `EXISTS`;
- [x] Вычислять `favorites_count` в SQL, не загружая идентификаторы всех
  пользователей, добавивших статью в favorites;
- [x] Объединить `article_tags` и `tags` одним batch JOIN-запросом, сохранив
  `position`;
- [x] Оставить `Statement.Dynamic` только для batch `IN article_ids`;
- [x] Использовать один и тот же read-model projection для list, feed и find, если
  это не ухудшает план SQLite;
- [x] Проверить `EXPLAIN QUERY PLAN` и добавить индекс только при подтверждённом
  полном скане на реальном запросе.

Count statement использует `Query.aggregate_one`.

Готово, когда число запросов не зависит от числа статей, favorites не
материализуются в OCaml, а list/feed/find возвращают прежний wire contract.

`EXPLAIN QUERY PLAN` для page query подтверждает `articles_created_at` для
порядка страницы, составные primary-key indexes для follows/favorites и
`favorites_article` для count. Дополнительная миграция индекса не требуется.

## 5. Покрыть application services изолированными тестами

- [x] Этап выполнен.

Hurl хорошо закрепляет HTTP contract, но не показывает точную границу
transaction и не позволяет удобно инъецировать редкие ошибки repository.
Функторы services уже дают необходимые seams для fake implementations.

Добавлены fake `Database`, repositories, `Clock` и `Password_hasher`, которые
проверяют:

- [x] Validation останавливает use case до открытия transaction;
- [x] Фиксированный `Clock.now` передаётся create/update statements;
- [x] Slug retry завершается успехом и имеет ограничение числа попыток;
- [x] Ошибка синхронизации тегов откатывает создание или обновление статьи;
- [x] Repository errors переводятся в правильные application errors;
- [x] Новый password хешируется только после успешной валидации;
- [x] Login не различает отсутствующий email и неверный пароль публичной ошибкой;
- [x] Follow-self, forbidden update/delete и отсутствующие сущности не смешиваются.

Тесты должны проверять observable calls и transaction outcome, а не повторять
реализацию service построчно.

## 6. Публиковать и проверять сгенерированный OpenAPI

- [x] Этап выполнен.

`typed-endpoint` хранит compiled endpoint graph; из него сервер строит OpenAPI
и монтирует runtime routes.

Реализовано:

- [x] Задать `Openapi.Config` для RealWorld API;
- [x] Отдавать compiled document по `/openapi.json`;
- [x] Добавить `/docs` и пять renderer routes, читающих тот же document;
- [x] Сохранить canonical OpenAPI snapshot или семантический golden test;
- [x] Проверять operation IDs, security alternatives optional auth, path/query
  codecs, request bodies, response statuses и component schemas;
- [x] Добавить Hurl smoke test для `/openapi.json`.

OpenAPI должен генерироваться из тех же declarations, которые монтируются в
Opium; отдельный вручную поддерживаемый YAML не нужен.

## 7. Отделить credentials от публичного пользователя

- [x] Этап выполнен.

Раньше `Domain.User.t` содержал `password_hash`, хотя обычные use cases и HTTP
responses не должны его видеть. Это увеличивало риск случайной сериализации или
логирования credential material.

Реализовано:

- [x] Удалить `password_hash` из обычного `Domain.User.t`;
- [x] Ввести repository-only `User_repository.credentials`, содержащий user и
  password hash;
- [x] Возвращать credentials только из lookup, используемого login;
- [x] Оставить register/update repositories принимающими hash как входное
  значение, но возвращающими безопасный `User.t`;
- [x] `Domain.User.Email.t` с нормализацией и валидацией на границе не позволяет
  repository принимать произвольную строку email;
- [x] Проверить, что DTO, errors и debug output не содержат password/hash.

Готово, когда controller и большинство application services не могут получить
password hash через тип обычного пользователя.

## 8. Перейти на compile-time proof ungrouped aggregate

- [x] Этап выполнен.

- [x] Использовать `Query.aggregate_one` вместо `Query.select_exactly_one` в
  count statement `article_queries.ml`;
- [x] Обновить inline SQL expect test, если rendering изменится;
- [x] Зафиксировать в `AGENTS.md`, что новый combinator обязателен для доказуемых
  ungrouped aggregates;
- [x] Оставить `select_exactly_one` только для форм, которые новый API ещё не
  выражает, с явным объяснением причины рядом с statement.

`Query.aggregate_one` доступен в `typed-sql 0.4.1`. В текущих SQL-модулях
`select_exactly_one` больше не используется.

## 9. Проверять SQLite и PostgreSQL перед релизом

- [ ] Завершить этап.

- [ ] Добавить `make test-postgres` в итоговую команду проверки перед релизом;
- [ ] сравнивать таблицы, ограничения и индексы, созданные миграциями SQLite и
  PostgreSQL, с учётом различий диалектов;
- [ ] завершать проверку ошибкой при расхождении схем или падении тестов любой
  из двух СУБД.

Готово, когда одна итоговая команда проверяет оба backend и обнаруживает
расхождение их схем до релиза.

## 10. Довести frontend до полного RealWorld

- [ ] Завершить этап.

- [ ] Добавить ленту статей и пагинацию;
- [ ] добавить страницу статьи с просмотром, созданием и удалением комментариев;
- [ ] добавить профили, избранные статьи и подписки;
- [ ] добавить редактирование и удаление статей, настройки пользователя.

Готово, когда все перечисленные сценарии доступны из интерфейса и используют
сгенерированный из OpenAPI клиент.

## 11. Сделать генерацию TypeScript-клиента воспроизводимой

- [ ] Завершить этап.

- [ ] Получать OpenAPI из compiled endpoint graph без запуска HTTP-сервера;
- [ ] генерировать TypeScript-клиент из локального документа;
- [ ] проверять, что сохранённый сгенерированный код соответствует текущему
  OpenAPI, и показывать расхождение в локальной проверке.

Готово, когда `make frontend-types` не требует запущенного backend, а изменение
контракта не проходит проверку с устаревшим клиентом.

## 12. Проверить PostgreSQL под нагрузкой

- [ ] Завершить этап.

- [ ] Проверить конкурентную регистрацию пользователей и создание статей с
  конфликтующими slug, включая итоговые данные и публичные ошибки;
- [ ] на наполненной БД изучить планы list/feed запросов через
  `EXPLAIN (ANALYZE, BUFFERS)`;
- [ ] менять запросы и индексы только при выявленной проблеме в планах.

Готово, когда конкурентные сценарии проходят без нарушения инвариантов, а
планы list/feed запросов проверены на данных представительного объёма.

## История выполнения

Пункты 1–7, переход на `Query.aggregate_one` и обновление typed-sql выполнены
следующими срезами:

1. profiles/follows без полных сканов и удаление мёртвых `all_*` statements;
2. scoped mutations вместе со структурированной классификацией конфликтов;
3. application-service и persistence integration tests для новых invariants;
4. компактный article read model;
5. OpenAPI endpoint и contract snapshot;
6. разделение `User.t` и credentials;
7. миграция на `Query.aggregate_one` после релиза typed-sql;
8. обновление до typed-sql 0.4.5: статические statements с
   `let%map.Parameters`, схема версии 2 и выбор SQL по диалекту для batch
   lookup пользователей.

Каждый срез должен завершаться `make check`. Изменения SQL statements должны
сохранять отдельный inline `[%expect]` непосредственно после объявления
statement, а изменение persistence semantics должно сопровождаться SQLite
integration test.
