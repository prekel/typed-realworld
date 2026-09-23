open! Base
open Typed_sql
module Domain = Realworld_domain.Domain
module Article_queries = Realworld_sqlite.Article_queries
module Comment_queries = Realworld_sqlite.Comment_queries
module User_queries = Realworld_sqlite.User_queries

let compile_exn dialect statement input = Statement.sql_exn ~dialect ~input statement

let filters : Domain.Article.filters =
  { tag = Some (Domain.Article.Tag.of_string_exn "ocaml")
  ; author = Some (Domain.User.Username.of_string_exn "alice")
  ; favorited_by = Some (Domain.User.Username.of_string_exn "bob")
  }
;;

let page =
  Domain.Page.create
    ~limit:(Domain.Page.Limit.of_int 20 |> Option.value_exn)
    ~offset:(Domain.Page.Offset.of_int 40 |> Option.value_exn)
    ()
;;

let slug value = Domain.Article.Slug.of_string_exn value
let username value = Domain.User.Username.of_string_exn value
let tag value = Domain.Article.Tag.of_string_exn value
let user_7 = Domain.User.Id.of_int64_exn 7L
let user_8 = Domain.User.Id.of_int64_exn 8L
let user_42 = Domain.User.Id.of_int64_exn 42L
let comment_3 = Domain.Comment.Id.of_int64_exn 3L

let now =
  Ptime.of_rfc3339 "2026-09-15T12:34:56Z" |> Result.ok |> Option.value_exn
  |> fun (time, _, _) -> time
;;

let%expect_test "article page compiles filtering, ordering and pagination" =
  let input : Article_queries.Page.Input.t = { filters; followed_by = None; page } in
  Stdlib.print_endline (compile_exn Dialect.Sqlite Article_queries.Page.statement input);
  [%expect
    {|
    SELECT
      t0."id",
      t0."author_id",
      t0."slug",
      t0."title",
      t0."description",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "articles" AS t0
    WHERE
      (
        (
          (?1 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "users" AS t1
            WHERE
              (
                (t1."id" = t0."author_id")
                AND (t1."username" = ?1)
              )
          ))
        )
        AND (
          (?2 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "article_tags" AS t1
            INNER JOIN "tags" AS t2
              ON (t1."tag_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."name" = ?2)
              )
          ))
        )
        AND (
          (?3 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "favorites" AS t1
            INNER JOIN "users" AS t2
              ON (t1."user_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."username" = ?3)
              )
          ))
        )
        AND (
          (?4 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "follows" AS t1
            WHERE
              (
                (t1."follower_id" = ?4)
                AND (t1."followed_id" = t0."author_id")
              )
          ))
        )
      )
    ORDER BY
      t0."created_at" DESC,
      t0."id" DESC
    LIMIT ?5
    OFFSET ?6
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Postgresql Article_queries.Page.statement input);
  [%expect
    {|
    SELECT
      t0."id",
      t0."author_id",
      t0."slug",
      t0."title",
      t0."description",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "articles" AS t0
    WHERE
      (
        (
          ($1 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "users" AS t1
            WHERE
              (
                (t1."id" = t0."author_id")
                AND (t1."username" = $1)
              )
          ))
        )
        AND (
          ($2 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "article_tags" AS t1
            INNER JOIN "tags" AS t2
              ON (t1."tag_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."name" = $2)
              )
          ))
        )
        AND (
          ($3 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "favorites" AS t1
            INNER JOIN "users" AS t2
              ON (t1."user_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."username" = $3)
              )
          ))
        )
        AND (
          ($4 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "follows" AS t1
            WHERE
              (
                (t1."follower_id" = $4)
                AND (t1."followed_id" = t0."author_id")
              )
          ))
        )
      )
    ORDER BY
      t0."created_at" DESC,
      t0."id" DESC
    LIMIT $5
    OFFSET $6
    |}]
;;

let%expect_test "article count reuses exactly the page predicates" =
  let input : Article_queries.Count.Input.t = { filters; followed_by = None } in
  Stdlib.print_endline (compile_exn Dialect.Sqlite Article_queries.Count.statement input);
  [%expect
    {|
    SELECT
      COUNT(*)
    FROM "articles" AS t0
    WHERE
      (
        (
          (?1 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "users" AS t1
            WHERE
              (
                (t1."id" = t0."author_id")
                AND (t1."username" = ?1)
              )
          ))
        )
        AND (
          (?2 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "article_tags" AS t1
            INNER JOIN "tags" AS t2
              ON (t1."tag_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."name" = ?2)
              )
          ))
        )
        AND (
          (?3 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "favorites" AS t1
            INNER JOIN "users" AS t2
              ON (t1."user_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."username" = ?3)
              )
          ))
        )
        AND (
          (?4 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "follows" AS t1
            WHERE
              (
                (t1."follower_id" = ?4)
                AND (t1."followed_id" = t0."author_id")
              )
          ))
        )
      )
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Postgresql Article_queries.Count.statement input);
  [%expect
    {|
    SELECT
      COUNT(*)
    FROM "articles" AS t0
    WHERE
      (
        (
          ($1 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "users" AS t1
            WHERE
              (
                (t1."id" = t0."author_id")
                AND (t1."username" = $1)
              )
          ))
        )
        AND (
          ($2 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "article_tags" AS t1
            INNER JOIN "tags" AS t2
              ON (t1."tag_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."name" = $2)
              )
          ))
        )
        AND (
          ($3 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "favorites" AS t1
            INNER JOIN "users" AS t2
              ON (t1."user_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."username" = $3)
              )
          ))
        )
        AND (
          ($4 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "follows" AS t1
            WHERE
              (
                (t1."follower_id" = $4)
                AND (t1."followed_id" = t0."author_id")
              )
          ))
        )
      )
    |}]
;;

let%expect_test "feed compiles as a correlated follows predicate" =
  let input : Article_queries.Page.Input.t =
    { filters = Domain.Article.no_filters; followed_by = Some user_42; page }
  in
  Stdlib.print_endline (compile_exn Dialect.Sqlite Article_queries.Page.statement input);
  [%expect
    {|
    SELECT
      t0."id",
      t0."author_id",
      t0."slug",
      t0."title",
      t0."description",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "articles" AS t0
    WHERE
      (
        (
          (?1 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "users" AS t1
            WHERE
              (
                (t1."id" = t0."author_id")
                AND (t1."username" = ?1)
              )
          ))
        )
        AND (
          (?2 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "article_tags" AS t1
            INNER JOIN "tags" AS t2
              ON (t1."tag_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."name" = ?2)
              )
          ))
        )
        AND (
          (?3 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "favorites" AS t1
            INNER JOIN "users" AS t2
              ON (t1."user_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."username" = ?3)
              )
          ))
        )
        AND (
          (?4 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "follows" AS t1
            WHERE
              (
                (t1."follower_id" = ?4)
                AND (t1."followed_id" = t0."author_id")
              )
          ))
        )
      )
    ORDER BY
      t0."created_at" DESC,
      t0."id" DESC
    LIMIT ?5
    OFFSET ?6
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Postgresql Article_queries.Page.statement input);
  [%expect
    {|
    SELECT
      t0."id",
      t0."author_id",
      t0."slug",
      t0."title",
      t0."description",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "articles" AS t0
    WHERE
      (
        (
          ($1 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "users" AS t1
            WHERE
              (
                (t1."id" = t0."author_id")
                AND (t1."username" = $1)
              )
          ))
        )
        AND (
          ($2 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "article_tags" AS t1
            INNER JOIN "tags" AS t2
              ON (t1."tag_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."name" = $2)
              )
          ))
        )
        AND (
          ($3 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "favorites" AS t1
            INNER JOIN "users" AS t2
              ON (t1."user_id" = t2."id")
            WHERE
              (
                (t1."article_id" = t0."id")
                AND (t2."username" = $3)
              )
          ))
        )
        AND (
          ($4 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "follows" AS t1
            WHERE
              (
                (t1."follower_id" = $4)
                AND (t1."followed_id" = t0."author_id")
              )
          ))
        )
      )
    ORDER BY
      t0."created_at" DESC,
      t0."id" DESC
    LIMIT $5
    OFFSET $6
    |}]
;;

let%expect_test "page hydration queries stay scoped to selected identifiers" =
  let article_ids = [ 101L; 102L ] in
  let author_ids = [ 7L; 8L ] in
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       Article_queries.Article_tags_by_article_ids.statement
       article_ids);
  [%expect
    {|
    SELECT
      t0."article_id",
      t0."tag_id",
      t0."position"
    FROM "article_tags" AS t0
    WHERE
      (t0."article_id" IN (
        ?1,
        ?2
      ))
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Postgresql
       Article_queries.Article_tags_by_article_ids.statement
       article_ids);
  [%expect
    {|
    SELECT
      t0."article_id",
      t0."tag_id",
      t0."position"
    FROM "article_tags" AS t0
    WHERE
      (t0."article_id" IN (
        $1,
        $2
      ))
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Article_queries.Tags_by_article_ids.statement article_ids);
  [%expect
    {|
    SELECT
      t0."id",
      t0."name"
    FROM "tags" AS t0
    WHERE
      (t0."id" IN (
        SELECT
          t1."tag_id"
        FROM "article_tags" AS t1
        WHERE
          (t1."article_id" IN (
            ?1,
            ?2
          ))
      ))
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Postgresql
       Article_queries.Tags_by_article_ids.statement
       article_ids);
  [%expect
    {|
    SELECT
      t0."id",
      t0."name"
    FROM "tags" AS t0
    WHERE
      (t0."id" IN (
        SELECT
          t1."tag_id"
        FROM "article_tags" AS t1
        WHERE
          (t1."article_id" IN (
            $1,
            $2
          ))
      ))
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       Article_queries.Favorites_by_article_ids.statement
       article_ids);
  [%expect
    {|
    SELECT
      t0."user_id",
      t0."article_id"
    FROM "favorites" AS t0
    WHERE
      (t0."article_id" IN (
        ?1,
        ?2
      ))
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Postgresql
       Article_queries.Favorites_by_article_ids.statement
       article_ids);
  [%expect
    {|
    SELECT
      t0."user_id",
      t0."article_id"
    FROM "favorites" AS t0
    WHERE
      (t0."article_id" IN (
        $1,
        $2
      ))
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite User_queries.Rows_by_ids.statement author_ids);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."id" IN (
        ?1,
        ?2
      ))
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Postgresql User_queries.Rows_by_ids.statement author_ids);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."id" IN (
        $1,
        $2
      ))
    |}];
  let input : User_queries.Follows_for_authors.Input.t =
    { viewer_id = user_42; author_ids }
  in
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite User_queries.Follows_for_authors.statement input);
  [%expect
    {|
    SELECT
      t0."follower_id",
      t0."followed_id"
    FROM "follows" AS t0
    WHERE
      (
        (t0."follower_id" = ?1)
        AND (t0."followed_id" IN (
          ?2,
          ?3
        ))
      )
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Postgresql User_queries.Follows_for_authors.statement input);
  [%expect
    {|
    SELECT
      t0."follower_id",
      t0."followed_id"
    FROM "follows" AS t0
    WHERE
      (
        (t0."follower_id" = $1)
        AND (t0."followed_id" IN (
          $2,
          $3
        ))
      )
    |}]
;;

let%expect_test "remaining article read queries compile" =
  Stdlib.print_endline (compile_exn Dialect.Sqlite Article_queries.All.statement ());
  [%expect
    {|
    SELECT
      t0."id",
      t0."author_id",
      t0."slug",
      t0."title",
      t0."description",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "articles" AS t0
    |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite Article_queries.All_tags.statement ());
  [%expect
    {|
    SELECT
      t0."id",
      t0."name"
    FROM "tags" AS t0
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Article_queries.All_article_tags.statement ());
  [%expect
    {|
    SELECT
      t0."article_id",
      t0."tag_id",
      t0."position"
    FROM "article_tags" AS t0
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Article_queries.All_favorites.statement ());
  [%expect
    {|
    SELECT
      t0."user_id",
      t0."article_id"
    FROM "favorites" AS t0
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Article_queries.By_slug.statement (slug "typed-sql"));
  [%expect
    {|
    SELECT
      t0."id",
      t0."author_id",
      t0."slug",
      t0."title",
      t0."description",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "articles" AS t0
    WHERE
      (t0."slug" = ?1)
    |}]
;;

let%expect_test "article write queries compile" =
  let article : Domain.Article.create =
    { title = "Typed SQL"
    ; description = "Compile SQL from typed builders"
    ; body = "Article body"
    ; tag_list = [ tag "ocaml"; tag "sql" ]
    }
  in
  let insert : Article_queries.Create_article.Input.t =
    { author_id = user_7
    ; slug = slug "typed-sql"
    ; title = article.title
    ; description = article.description
    ; body = article.body
    ; now
    }
  in
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Article_queries.Create_article.statement insert);
  [%expect
    {|
    INSERT INTO "articles" (
      "author_id",
      "slug",
      "title",
      "description",
      "body",
      "created_at",
      "updated_at"
    )
    VALUES
      (?1, ?2, ?3, ?4, ?5, ?6, ?6)
    RETURNING
      "id",
      "author_id",
      "slug",
      "title",
      "description",
      "body",
      "created_at",
      "updated_at"
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       Article_queries.Update_article.statement
       { id = 101L
       ; slug = slug "typed-sql-updated"
       ; title = "Typed SQL updated"
       ; description = "Updated description"
       ; body = "Updated body"
       ; now
       });
  [%expect
    {|
    UPDATE "articles"
    SET
      "slug" = ?1,
      "title" = ?2,
      "description" = ?3,
      "body" = ?4,
      "updated_at" = ?5
    WHERE
      ("id" = ?6)
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Article_queries.Delete_article.statement 101L);
  [%expect
    {|
    DELETE FROM "articles"
    WHERE
      ("id" = ?1)
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Article_queries.Upsert_tag.statement (tag "ocaml"));
  [%expect
    {|
    INSERT INTO "tags" AS t0 (
      "name"
    )
    VALUES
      (?1)
    ON CONFLICT (
      "name"
    )
    DO UPDATE
    SET
      "name" = excluded."name"
    RETURNING
      "id",
      "name"
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Postgresql Article_queries.Upsert_tag.statement (tag "ocaml"));
  [%expect
    {|
    INSERT INTO "tags" AS t0 (
      "name"
    )
    VALUES
      ($1)
    ON CONFLICT (
      "name"
    )
    DO UPDATE
    SET
      "name" = excluded."name"
    RETURNING
      "id",
      "name"
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Article_queries.Clear_tags.statement 101L);
  [%expect
    {|
    DELETE FROM "article_tags"
    WHERE
      ("article_id" = ?1)
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       Article_queries.Attach_tag.statement
       { article_id = 101L; tag_id = 5L; position = 1 });
  [%expect
    {|
    INSERT INTO "article_tags" (
      "article_id",
      "tag_id",
      "position"
    )
    VALUES
      (?1, ?2, ?3)
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       Article_queries.Add_favorite.statement
       { user_id = user_7; article_id = 101L });
  [%expect
    {|
    INSERT INTO "favorites" (
      "user_id",
      "article_id"
    )
    VALUES
      (?1, ?2)
    ON CONFLICT DO NOTHING
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       Article_queries.Remove_favorite.statement
       { user_id = user_7; article_id = 101L });
  [%expect
    {|
    DELETE FROM "favorites"
    WHERE
      (
        ("user_id" = ?1)
        AND ("article_id" = ?2)
      )
    |}]
;;

let%expect_test "comment queries compile" =
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       Comment_queries.Article_by_slug.statement
       (slug "typed-sql"));
  [%expect
    {|
    SELECT
      t0."id",
      t0."author_id",
      t0."slug",
      t0."title",
      t0."description",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "articles" AS t0
    WHERE
      (t0."slug" = ?1)
    |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite Comment_queries.All.statement ());
  [%expect
    {|
    SELECT
      t0."id",
      t0."article_id",
      t0."author_id",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "comments" AS t0
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Comment_queries.By_article.statement 101L);
  [%expect
    {|
    SELECT
      t0."id",
      t0."article_id",
      t0."author_id",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "comments" AS t0
    WHERE
      (t0."article_id" = ?1)
    ORDER BY
      t0."created_at" ASC,
      t0."id" ASC
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       Comment_queries.By_article_and_id.statement
       { article_id = 101L; comment_id = comment_3 });
  [%expect
    {|
    SELECT
      t0."id",
      t0."article_id",
      t0."author_id",
      t0."body",
      t0."created_at",
      t0."updated_at"
    FROM "comments" AS t0
    WHERE
      (
        (t0."id" = ?1)
        AND (t0."article_id" = ?2)
      )
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       Comment_queries.Create_comment.statement
       { article_id = 101L; author_id = user_7; body = "A comment"; now });
  [%expect
    {|
    INSERT INTO "comments" (
      "article_id",
      "author_id",
      "body",
      "created_at",
      "updated_at"
    )
    VALUES
      (?1, ?2, ?3, ?4, ?4)
    RETURNING
      "id",
      "article_id",
      "author_id",
      "body",
      "created_at",
      "updated_at"
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite Comment_queries.Delete_comment.statement comment_3);
  [%expect
    {|
    DELETE FROM "comments"
    WHERE
      ("id" = ?1)
    |}]
;;

let%expect_test "remaining user queries compile" =
  Stdlib.print_endline (compile_exn Dialect.Sqlite User_queries.All_rows.statement ());
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite User_queries.All_follows.statement ());
  [%expect
    {|
    SELECT
      t0."follower_id",
      t0."followed_id"
    FROM "follows" AS t0
    |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite User_queries.By_id.statement user_7);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."id" = ?1)
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite User_queries.By_email.statement "alice@example.com");
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."email" = ?1)
    |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite User_queries.By_username.statement (username "alice"));
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."username" = ?1)
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       User_queries.Create_user.statement
       { email = "alice@example.com"
       ; username = username "alice"
       ; password_hash = "hash"
       });
  [%expect
    {|
    INSERT INTO "users" (
      "email",
      "username",
      "password_hash",
      "bio",
      "image"
    )
    VALUES
      (?1, ?2, ?3, ?4, ?5)
    RETURNING
      "id",
      "email",
      "username",
      "password_hash",
      "bio",
      "image"
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       User_queries.Update_user.statement
       { id = user_7
       ; email = "alice@example.com"
       ; username = username "alice"
       ; password_hash = "new-hash"
       ; bio = Some "OCaml developer"
       ; image = None
       });
  [%expect
    {|
    UPDATE "users"
    SET
      "email" = ?1,
      "username" = ?2,
      "password_hash" = ?3,
      "bio" = ?4,
      "image" = ?5
    WHERE
      ("id" = ?6)
    RETURNING
      "id",
      "email",
      "username",
      "password_hash",
      "bio",
      "image"
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       User_queries.Follow_user.statement
       { follower_id = user_7; followed_id = user_8 });
  [%expect
    {|
    INSERT INTO "follows" (
      "follower_id",
      "followed_id"
    )
    VALUES
      (?1, ?2)
    ON CONFLICT DO NOTHING
    |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       User_queries.Unfollow_user.statement
       { follower_id = user_7; followed_id = user_8 });
  [%expect
    {|
    DELETE FROM "follows"
    WHERE
      (
        ("follower_id" = ?1)
        AND ("followed_id" = ?2)
      )
    |}]
;;
