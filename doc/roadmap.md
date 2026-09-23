# Дорожная карта

## Текущее состояние

Приложение реализует полный HTTP-контракт RealWorld: регистрацию и login,
current user, profiles и follows, articles, feed, tags, favorites и comments.
Контроллеры собраны через `typed-endpoint`, application services задают
transaction boundaries, SQLite repositories используют `typed-sql`, а схема
изменяется только версионированными dbmate migrations.

`make check` проверяет форматирование, сборку, unit и SQLite integration tests,
162 Hurl requests, документацию, opam package и соответствие `db/schema.json`
миграциям.

Следующие этапы не расширяют RealWorld wire contract. Они устраняют оставшиеся
полные сканы, усиливают persistence invariants, сокращают число и объём
запросов и делают внутренние границы безопаснее.

## Достаточность текущего typed-sql

Для этапов 1–7 достаточно `typed-sql 0.3.1`. Уже доступны необходимые
возможности:

- `JOIN`, correlated `EXISTS`, aggregates, scalar subqueries и applicative
  projections для read models;
- nullable parameters и `Query.where_optional_param` для одного статического
  SQL shape;
- `WHERE` в `UPDATE`/`DELETE`, `RETURNING`, `expect_optional` и
  `expect_one` для scoped mutations;
- target-specific `ON CONFLICT`, `DO UPDATE` и `DO NOTHING`;
- `Statement.Dynamic` для batch `IN`, где число идентификаторов действительно
  меняет SQL shape;
- структурированная классификация constraint violations в Caqti adapter.

Некоторые доказательства aggregates в `0.3.1` выполняются compiler-ом при
создании statement, а не системой типов OCaml. Это не блокирует реализацию
read models: некорректный statement всё равно не запускается, но ошибка пока не
является compile-time type error.

Только этап 8 зависит от будущего `Query.aggregate_one`. Он заменит
`Query.select_exactly_one` настоящим compile-time proof для ungrouped
aggregate. `Expr.coalesce`, `Query.select_one` и `Query.default_if_empty` для
текущего RealWorld API не требуются.

## 1. Убрать полные сканы profiles и follows

Сейчас получение одного профиля читает все строки `users` и `follows`.
`follow` и `unfollow` после изменения связи снова читают всю таблицу follows,
чтобы построить один response.

Нужно:

- добавить `profile_by_username`, выбирающий одного пользователя;
- вычислять `following` через correlated `EXISTS` только для текущего viewer;
- после успешного `follow` строить response с `following = true`, после
  `unfollow` — с `following = false`, не перечитывая все связи;
- удалить `User_queries.all_rows`, `User_queries.all_follows` и ставшие
  ненужными helpers из `repository_support.ml`;
- сохранить корректное поведение optional auth: без viewer поле `following`
  равно `false`.

Готово, когда profile/follow/unfollow не содержат запросов без ограничения по
username, user ID или конкретной паре follower/followed, а SQLite integration
tests проверяют оба значения `following`.

## 2. Включить ownership в mutation SQL

Проверка владельца и mutation уже выполняются в одной транзакции, но текущие
`UPDATE`/`DELETE` ограничены только идентификатором сущности. Сам mutation
должен повторно выражать authorization invariant в своём `WHERE`.

Нужно:

- обновлять статью с `WHERE article.id = ? AND article.author_id = ?`;
- удалять статью с тем же ownership scope;
- удалять комментарий с ограничением по comment ID, article ID и author ID;
- использовать `RETURNING` и `expect_optional`, чтобы отличать выполненный
  mutation от исчезнувшей или изменившейся строки;
- сохранить предварительный lookup только там, где он нужен для различения
  `Not_found` и `Forbidden`;
- проверить rollback всей операции, включая изменения тегов.

Готово, когда ни один ownership-sensitive mutation нельзя выполнить SQL-запросом
только по публичному идентификатору и integration tests проверяют чужого
владельца и удалённую между lookup и mutation строку.

## 3. Сохранить структурированные persistence errors

Сейчас `Repository_support.run` сразу превращает adapter error в строковый
`Persistence_error`, а создание статьи распознаёт конфликт slug поиском слова
`constraint`. Это смешивает unique, foreign-key и check violations и плохо
ведёт себя при конкурентных запросах.

Нужно:

- классифицировать `Typed_sql_caqti_lwt.Constraint_violation` до преобразования
  в публичный `Persistence_error`;
- для статьи переводить только unique violation операции записи slug в
  `Slug_taken`;
- после unique conflict пользователя перечитывать email и username и
  определять `Email_taken`/`Username_taken` по данным, не по тексту сообщения
  драйвера;
- одинаково обрабатывать conflict при create и update;
- не возвращать внутреннее сообщение SQLite через HTTP;
- добавить integration tests для case-insensitive конфликтов и конфликтов,
  возникающих после предварительного lookup.

Для этого не требуется более детальная ошибка от `typed-sql`: текущего
constraint kind достаточно, а конкретный business conflict можно установить
повторным typed lookup внутри той же transaction boundary.

## 4. Сократить article read model

Текущая страница статей после основного SELECT отдельно загружает авторов,
подписки, tags, article-tags и все favorite rows выбранных статей. Это не N+1,
но объём favorites растёт вместе с полной популярностью статьи, а не с размером
страницы.

Нужно:

- присоединять автора к основному article query;
- вычислять `following` и `favorited` через correlated `EXISTS`;
- вычислять `favorites_count` в SQL, не загружая идентификаторы всех
  пользователей, добавивших статью в favorites;
- объединить `article_tags` и `tags` одним batch JOIN-запросом, сохранив
  `position`;
- оставить `Statement.Dynamic` только для batch `IN article_ids`;
- использовать один и тот же read-model projection для list, feed и find, если
  это не ухудшает план SQLite;
- проверить `EXPLAIN QUERY PLAN` и добавить индекс только при подтверждённом
  полном скане на реальном запросе.

В `typed-sql 0.3.1` count можно выразить текущим aggregate/scalar-subquery API
или отдельным grouped batch query. Будущий `Query.aggregate_one` сделает proof
нагляднее, но для этой оптимизации не обязателен.

Готово, когда число запросов не зависит от числа статей, favorites не
материализуются в OCaml, а list/feed/find возвращают прежний wire contract.

## 5. Покрыть application services изолированными тестами

Hurl хорошо закрепляет HTTP contract, но не показывает точную границу
transaction и не позволяет удобно инъецировать редкие ошибки repository.
Функторы services уже дают необходимые seams для fake implementations.

Нужно добавить fake `Database`, repositories, `Clock` и `Password_hasher` и
проверить:

- validation останавливает use case до открытия transaction;
- фиксированный `Clock.now` передаётся create/update statements;
- slug retry завершается успехом и имеет ограничение числа попыток;
- ошибка синхронизации тегов откатывает создание или обновление статьи;
- repository errors переводятся в правильные application errors;
- новый password хешируется только после успешной валидации;
- login не различает отсутствующий email и неверный пароль публичной ошибкой;
- follow-self, forbidden update/delete и отсутствующие сущности не смешиваются.

Тесты должны проверять observable calls и transaction outcome, а не повторять
реализацию service построчно.

## 6. Публиковать и проверять сгенерированный OpenAPI

`typed-endpoint` уже хранит полный compiled endpoint graph и умеет строить
OpenAPI, но сервер пока монтирует только runtime routes.

Нужно:

- задать `Openapi.Config` для RealWorld API;
- отдавать compiled document по `/openapi.json`;
- при необходимости добавить простую `/docs`, читающую тот же document;
- сохранить canonical OpenAPI snapshot или семантический golden test;
- проверять operation IDs, security alternatives optional auth, path/query
  codecs, request bodies, response statuses и component schemas;
- добавить Hurl smoke test для `/openapi.json`.

OpenAPI должен генерироваться из тех же declarations, которые монтируются в
Opium; отдельный вручную поддерживаемый YAML не нужен.

## 7. Отделить credentials от публичного пользователя

`Domain.User.t` сейчас содержит `password_hash`, хотя обычные use cases и HTTP
responses не должны его видеть. Это увеличивает риск случайной сериализации или
логирования credential material.

Нужно:

- удалить `password_hash` из обычного `Domain.User.t`;
- ввести repository-only authentication record, например
  `User_credentials.t`, содержащий user и password hash;
- возвращать credentials только из lookup, используемого login;
- оставить register/update repositories принимающими hash как входное
  значение, но возвращающими безопасный `User.t`;
- рассмотреть `Domain.User.Email.t` с нормализацией и валидацией на границе,
  чтобы repository не принимал произвольную строку email;
- проверить, что DTO, errors и debug output не содержат password/hash.

Готово, когда controller и большинство application services не могут получить
password hash через тип обычного пользователя.

## 8. Перейти на compile-time proof ungrouped aggregate

После выпуска соответствующей версии `typed-sql` заменить count statement в
`article_queries.ml`:

- использовать `Query.aggregate_one` вместо `Query.select_exactly_one`;
- обновить inline SQL expect test, если rendering изменится;
- зафиксировать в `AGENTS.md`, что новый combinator обязателен для доказуемых
  ungrouped aggregates;
- оставить `select_exactly_one` только для форм, которые новый API ещё не
  выражает, с явным объяснением причины рядом с statement.

Этот этап зависит от будущего API `typed-sql`. Он не блокирует этапы 1–7 и не
меняет SQL или поведение приложения сам по себе.

## Порядок выполнения

Рекомендуемые срезы:

1. profiles/follows без полных сканов и удаление мёртвых `all_*` statements;
2. scoped mutations вместе со структурированной классификацией конфликтов;
3. application-service и persistence integration tests для новых invariants;
4. компактный article read model;
5. OpenAPI endpoint и contract snapshot;
6. разделение `User.t` и credentials;
7. миграция на `Query.aggregate_one` после релиза typed-sql.

Каждый срез должен завершаться `make check`. Изменения SQL statements должны
сохранять отдельный inline `[%expect]` непосредственно после объявления
statement, а изменение persistence semantics должно сопровождаться SQLite
integration test.
