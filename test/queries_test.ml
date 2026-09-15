open! Base
open Typed_sql
module Domain = Realworld_domain.Domain
module Article_queries = Realworld_sqlite.Article_queries
module Comment_queries = Realworld_sqlite.Comment_queries
module User_queries = Realworld_sqlite.User_queries

let compile_exn dialect query =
  Compiler.compile ~dialect query
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
  |> Compiled_query.sql
;;

let compile_command_exn dialect command =
  Compiler.compile_command ~dialect command
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
  |> Compiled_command.sql
;;

let filters : Domain.Article.filters =
  { tag = Some "ocaml"; author = Some "alice"; favorited_by = Some "bob" }
;;

let page = Domain.Page.{ limit = 20; offset = 40 }

let now =
  Ptime.of_rfc3339 "2026-09-15T12:34:56Z" |> Result.ok |> Option.value_exn
  |> fun (time, _, _) -> time
;;

let%expect_test "article page compiles filtering, ordering and pagination" =
  let query = Article_queries.page ~filters ~followed_by:None ~page in
  Stdlib.print_endline (compile_exn Dialect.Sqlite query);
  [%expect
    {|
    SELECT t0."id", t0."author_id", t0."slug", t0."title", t0."description", t0."body", t0."created_at", t0."updated_at" FROM "articles" AS t0 WHERE ((EXISTS (SELECT 1 FROM "users" AS t1 WHERE ((t1."id" = t0."author_id") AND (t1."username" = ?1)))) AND (EXISTS (SELECT 1 FROM "article_tags" AS t1 INNER JOIN "tags" AS t2 ON (t1."tag_id" = t2."id") WHERE ((t1."article_id" = t0."id") AND (t2."name" = ?2)))) AND (EXISTS (SELECT 1 FROM "favorites" AS t1 INNER JOIN "users" AS t2 ON (t1."user_id" = t2."id") WHERE ((t1."article_id" = t0."id") AND (t2."username" = ?3))))) ORDER BY t0."created_at" DESC, t0."id" DESC LIMIT 20 OFFSET 40
    |}];
  Stdlib.print_endline (compile_exn Dialect.Postgresql query);
  [%expect
    {|
    SELECT t0."id", t0."author_id", t0."slug", t0."title", t0."description", t0."body", t0."created_at", t0."updated_at" FROM "articles" AS t0 WHERE ((EXISTS (SELECT 1 FROM "users" AS t1 WHERE ((t1."id" = t0."author_id") AND (t1."username" = $1)))) AND (EXISTS (SELECT 1 FROM "article_tags" AS t1 INNER JOIN "tags" AS t2 ON (t1."tag_id" = t2."id") WHERE ((t1."article_id" = t0."id") AND (t2."name" = $2)))) AND (EXISTS (SELECT 1 FROM "favorites" AS t1 INNER JOIN "users" AS t2 ON (t1."user_id" = t2."id") WHERE ((t1."article_id" = t0."id") AND (t2."username" = $3))))) ORDER BY t0."created_at" DESC, t0."id" DESC LIMIT 20 OFFSET 40
    |}]
;;

let%expect_test "article count reuses exactly the page predicates" =
  let query = Article_queries.count ~filters ~followed_by:None in
  Stdlib.print_endline (compile_exn Dialect.Sqlite query);
  [%expect
    {|
    SELECT COUNT(*) FROM "articles" AS t0 WHERE ((EXISTS (SELECT 1 FROM "users" AS t1 WHERE ((t1."id" = t0."author_id") AND (t1."username" = ?1)))) AND (EXISTS (SELECT 1 FROM "article_tags" AS t1 INNER JOIN "tags" AS t2 ON (t1."tag_id" = t2."id") WHERE ((t1."article_id" = t0."id") AND (t2."name" = ?2)))) AND (EXISTS (SELECT 1 FROM "favorites" AS t1 INNER JOIN "users" AS t2 ON (t1."user_id" = t2."id") WHERE ((t1."article_id" = t0."id") AND (t2."username" = ?3)))))
    |}];
  Stdlib.print_endline (compile_exn Dialect.Postgresql query);
  [%expect
    {|
    SELECT COUNT(*) FROM "articles" AS t0 WHERE ((EXISTS (SELECT 1 FROM "users" AS t1 WHERE ((t1."id" = t0."author_id") AND (t1."username" = $1)))) AND (EXISTS (SELECT 1 FROM "article_tags" AS t1 INNER JOIN "tags" AS t2 ON (t1."tag_id" = t2."id") WHERE ((t1."article_id" = t0."id") AND (t2."name" = $2)))) AND (EXISTS (SELECT 1 FROM "favorites" AS t1 INNER JOIN "users" AS t2 ON (t1."user_id" = t2."id") WHERE ((t1."article_id" = t0."id") AND (t2."username" = $3)))))
    |}]
;;

let%expect_test "feed compiles as a correlated follows predicate" =
  let query =
    Article_queries.page ~filters:Domain.Article.no_filters ~followed_by:(Some 42) ~page
  in
  Stdlib.print_endline (compile_exn Dialect.Sqlite query);
  [%expect
    {|
    SELECT t0."id", t0."author_id", t0."slug", t0."title", t0."description", t0."body", t0."created_at", t0."updated_at" FROM "articles" AS t0 WHERE (EXISTS (SELECT 1 FROM "follows" AS t1 WHERE ((t1."follower_id" = ?1) AND (t1."followed_id" = t0."author_id")))) ORDER BY t0."created_at" DESC, t0."id" DESC LIMIT 20 OFFSET 40
    |}];
  Stdlib.print_endline (compile_exn Dialect.Postgresql query);
  [%expect
    {|
    SELECT t0."id", t0."author_id", t0."slug", t0."title", t0."description", t0."body", t0."created_at", t0."updated_at" FROM "articles" AS t0 WHERE (EXISTS (SELECT 1 FROM "follows" AS t1 WHERE ((t1."follower_id" = $1) AND (t1."followed_id" = t0."author_id")))) ORDER BY t0."created_at" DESC, t0."id" DESC LIMIT 20 OFFSET 40
    |}]
;;

let%expect_test "page hydration queries stay scoped to selected identifiers" =
  let article_ids = [ 101L; 102L ] in
  let author_ids = [ 7L; 8L ] in
  let query = Article_queries.article_tags_by_article_ids article_ids in
  Stdlib.print_endline (compile_exn Dialect.Sqlite query);
  [%expect
    {|
    SELECT t0."article_id", t0."tag_id", t0."position" FROM "article_tags" AS t0 WHERE (t0."article_id" IN (?1, ?2))
    |}];
  Stdlib.print_endline (compile_exn Dialect.Postgresql query);
  [%expect
    {|
    SELECT t0."article_id", t0."tag_id", t0."position" FROM "article_tags" AS t0 WHERE (t0."article_id" IN ($1, $2))
    |}];
  let query = Article_queries.tags_by_article_ids article_ids in
  Stdlib.print_endline (compile_exn Dialect.Sqlite query);
  [%expect
    {|
    SELECT t0."id", t0."name" FROM "tags" AS t0 WHERE (t0."id" IN (SELECT t1."tag_id" FROM "article_tags" AS t1 WHERE (t1."article_id" IN (?1, ?2))))
    |}];
  Stdlib.print_endline (compile_exn Dialect.Postgresql query);
  [%expect
    {|
    SELECT t0."id", t0."name" FROM "tags" AS t0 WHERE (t0."id" IN (SELECT t1."tag_id" FROM "article_tags" AS t1 WHERE (t1."article_id" IN ($1, $2))))
    |}];
  let query = Article_queries.favorites_by_article_ids article_ids in
  Stdlib.print_endline (compile_exn Dialect.Sqlite query);
  [%expect
    {|
    SELECT t0."user_id", t0."article_id" FROM "favorites" AS t0 WHERE (t0."article_id" IN (?1, ?2))
    |}];
  Stdlib.print_endline (compile_exn Dialect.Postgresql query);
  [%expect
    {|
    SELECT t0."user_id", t0."article_id" FROM "favorites" AS t0 WHERE (t0."article_id" IN ($1, $2))
    |}];
  let query = User_queries.rows_by_ids author_ids in
  Stdlib.print_endline (compile_exn Dialect.Sqlite query);
  [%expect
    {|
    SELECT t0."id", t0."email", t0."username", t0."password_hash", t0."bio", t0."image" FROM "users" AS t0 WHERE (t0."id" IN (?1, ?2))
    |}];
  Stdlib.print_endline (compile_exn Dialect.Postgresql query);
  [%expect
    {|
    SELECT t0."id", t0."email", t0."username", t0."password_hash", t0."bio", t0."image" FROM "users" AS t0 WHERE (t0."id" IN ($1, $2))
    |}];
  let query = User_queries.follows_for_authors ~viewer_id:42 author_ids in
  Stdlib.print_endline (compile_exn Dialect.Sqlite query);
  [%expect
    {|
    SELECT t0."follower_id", t0."followed_id" FROM "follows" AS t0 WHERE ((t0."follower_id" = ?1) AND (t0."followed_id" IN (?2, ?3)))
    |}];
  Stdlib.print_endline (compile_exn Dialect.Postgresql query);
  [%expect
    {|
    SELECT t0."follower_id", t0."followed_id" FROM "follows" AS t0 WHERE ((t0."follower_id" = $1) AND (t0."followed_id" IN ($2, $3)))
    |}]
;;

let%expect_test "remaining article read queries compile" =
  Stdlib.print_endline (compile_exn Dialect.Sqlite (Article_queries.all ()));
  [%expect
    {| SELECT t0."id", t0."author_id", t0."slug", t0."title", t0."description", t0."body", t0."created_at", t0."updated_at" FROM "articles" AS t0 |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (Article_queries.all_tags ()));
  [%expect {| SELECT t0."id", t0."name" FROM "tags" AS t0 |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (Article_queries.all_article_tags ()));
  [%expect
    {| SELECT t0."article_id", t0."tag_id", t0."position" FROM "article_tags" AS t0 |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (Article_queries.all_favorites ()));
  [%expect {| SELECT t0."user_id", t0."article_id" FROM "favorites" AS t0 |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (Article_queries.by_slug "typed-sql"));
  [%expect
    {| SELECT t0."id", t0."author_id", t0."slug", t0."title", t0."description", t0."body", t0."created_at", t0."updated_at" FROM "articles" AS t0 WHERE (t0."slug" = ?1) |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (Article_queries.tag_by_name "ocaml"));
  [%expect {| SELECT t0."id", t0."name" FROM "tags" AS t0 WHERE (t0."name" = ?1) |}]
;;

let%expect_test "article write queries compile" =
  let article : Domain.Article.create =
    { title = "Typed SQL"
    ; description = "Compile SQL from typed builders"
    ; body = "Article body"
    ; tag_list = [ "ocaml"; "sql" ]
    }
  in
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       (Article_queries.insert ~author_id:7 ~slug:"typed-sql" ~now article));
  [%expect
    {| INSERT INTO "articles" ("author_id", "slug", "title", "description", "body", "created_at", "updated_at") VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) RETURNING "id", "author_id", "slug", "title", "description", "body", "created_at", "updated_at" |}];
  Stdlib.print_endline
    (compile_command_exn
       Dialect.Sqlite
       (Article_queries.update
          ~id:101L
          ~slug:"typed-sql-updated"
          ~title:"Typed SQL updated"
          ~description:"Updated description"
          ~body:"Updated body"
          ~now));
  [%expect
    {| UPDATE "articles" SET "slug" = ?1, "title" = ?2, "description" = ?3, "body" = ?4, "updated_at" = ?5 WHERE ("id" = ?6) |}];
  Stdlib.print_endline (compile_command_exn Dialect.Sqlite (Article_queries.delete 101L));
  [%expect {| DELETE FROM "articles" WHERE ("id" = ?1) |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (Article_queries.insert_tag "ocaml"));
  [%expect {| INSERT INTO "tags" ("name") VALUES (?1) RETURNING "id", "name" |}];
  Stdlib.print_endline
    (compile_command_exn Dialect.Sqlite (Article_queries.clear_tags 101L));
  [%expect {| DELETE FROM "article_tags" WHERE ("article_id" = ?1) |}];
  Stdlib.print_endline
    (compile_command_exn
       Dialect.Sqlite
       (Article_queries.attach_tag ~article_id:101L ~tag_id:5L ~position:1));
  [%expect
    {| INSERT INTO "article_tags" ("article_id", "tag_id", "position") VALUES (?1, ?2, ?3) |}];
  Stdlib.print_endline
    (compile_command_exn
       Dialect.Sqlite
       (Article_queries.add_favorite ~user_id:7 ~article_id:101L));
  [%expect
    {| INSERT INTO "favorites" ("user_id", "article_id") VALUES (?1, ?2) ON CONFLICT DO NOTHING |}];
  Stdlib.print_endline
    (compile_command_exn
       Dialect.Sqlite
       (Article_queries.remove_favorite ~user_id:7 ~article_id:101L));
  [%expect {| DELETE FROM "favorites" WHERE (("user_id" = ?1) AND ("article_id" = ?2)) |}]
;;

let%expect_test "comment queries compile" =
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite (Comment_queries.article_by_slug "typed-sql"));
  [%expect
    {| SELECT t0."id", t0."author_id", t0."slug", t0."title", t0."description", t0."body", t0."created_at", t0."updated_at" FROM "articles" AS t0 WHERE (t0."slug" = ?1) |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (Comment_queries.all ()));
  [%expect
    {| SELECT t0."id", t0."article_id", t0."author_id", t0."body", t0."created_at", t0."updated_at" FROM "comments" AS t0 |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (Comment_queries.by_article 101L));
  [%expect
    {| SELECT t0."id", t0."article_id", t0."author_id", t0."body", t0."created_at", t0."updated_at" FROM "comments" AS t0 WHERE (t0."article_id" = ?1) ORDER BY t0."created_at" ASC, t0."id" ASC |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       (Comment_queries.by_article_and_id ~article_id:101L ~comment_id:3));
  [%expect
    {| SELECT t0."id", t0."article_id", t0."author_id", t0."body", t0."created_at", t0."updated_at" FROM "comments" AS t0 WHERE ((t0."id" = ?1) AND (t0."article_id" = ?2)) |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       (Comment_queries.insert ~article_id:101L ~author_id:7 ~body:"A comment" ~now));
  [%expect
    {| INSERT INTO "comments" ("article_id", "author_id", "body", "created_at", "updated_at") VALUES (?1, ?2, ?3, ?4, ?5) RETURNING "id", "article_id", "author_id", "body", "created_at", "updated_at" |}];
  Stdlib.print_endline (compile_command_exn Dialect.Sqlite (Comment_queries.delete 3L));
  [%expect {| DELETE FROM "comments" WHERE ("id" = ?1) |}]
;;

let%expect_test "remaining user queries compile" =
  Stdlib.print_endline (compile_exn Dialect.Sqlite (User_queries.all_rows ()));
  [%expect
    {| SELECT t0."id", t0."email", t0."username", t0."password_hash", t0."bio", t0."image" FROM "users" AS t0 |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (User_queries.all_follows ()));
  [%expect {| SELECT t0."follower_id", t0."followed_id" FROM "follows" AS t0 |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (User_queries.by_id 7));
  [%expect
    {| SELECT t0."id", t0."email", t0."username", t0."password_hash", t0."bio", t0."image" FROM "users" AS t0 WHERE (t0."id" = ?1) |}];
  Stdlib.print_endline
    (compile_exn Dialect.Sqlite (User_queries.by_email "alice@example.com"));
  [%expect
    {| SELECT t0."id", t0."email", t0."username", t0."password_hash", t0."bio", t0."image" FROM "users" AS t0 WHERE (t0."email" = ?1) |}];
  Stdlib.print_endline (compile_exn Dialect.Sqlite (User_queries.by_username "alice"));
  [%expect
    {| SELECT t0."id", t0."email", t0."username", t0."password_hash", t0."bio", t0."image" FROM "users" AS t0 WHERE (t0."username" = ?1) |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       (User_queries.insert
          ~email:"alice@example.com"
          ~username:"alice"
          ~password_hash:"hash"));
  [%expect
    {| INSERT INTO "users" ("email", "username", "password_hash", "bio", "image") VALUES (?1, ?2, ?3, ?4, ?5) RETURNING "id", "email", "username", "password_hash", "bio", "image" |}];
  Stdlib.print_endline
    (compile_exn
       Dialect.Sqlite
       (User_queries.update
          ~id:7
          ~email:"alice@example.com"
          ~username:"alice"
          ~password_hash:"new-hash"
          ~bio:(Some "OCaml developer")
          ~image:None));
  [%expect
    {| UPDATE "users" SET "email" = ?1, "username" = ?2, "password_hash" = ?3, "bio" = ?4, "image" = ?5 WHERE ("id" = ?6) RETURNING "id", "email", "username", "password_hash", "bio", "image" |}];
  Stdlib.print_endline
    (compile_command_exn
       Dialect.Sqlite
       (User_queries.follow ~follower_id:7 ~followed_id:8L));
  [%expect
    {| INSERT INTO "follows" ("follower_id", "followed_id") VALUES (?1, ?2) ON CONFLICT DO NOTHING |}];
  Stdlib.print_endline
    (compile_command_exn
       Dialect.Sqlite
       (User_queries.unfollow ~follower_id:7 ~followed_id:8L));
  [%expect
    {| DELETE FROM "follows" WHERE (("follower_id" = ?1) AND ("followed_id" = ?2)) |}]
;;
