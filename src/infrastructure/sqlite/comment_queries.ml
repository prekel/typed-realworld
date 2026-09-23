open! Base
open Typed_sql
open Infix
module Domain = Realworld_domain.Domain
module Articles = Schema.Articles
module Comments = Schema.Comments

let article_by_slug =
  Statement.Portable.query_optional_exn (fun params ->
    let slug = params.column Articles.slug_column ~get:Domain.Article.Slug.to_string in
    Query.(
      from Articles.table
      |> where (fun article -> Articles.slug article =. slug)
      |> limit_one
      |> select Articles.projection))
;;

let%expect_test "article by slug SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite article_by_slug);
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
    LIMIT 1
    |}]
;;

let all : (unit, Comments.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Comments.table |> select Comments.projection))
;;

let%expect_test "all comments SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite all);
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
    |}]
;;

let by_article =
  Statement.Portable.query_many_exn (fun params ->
    let article_id = params.column Comments.article_id_column ~get:Fn.id in
    Query.(
      from Comments.table
      |> where (fun comment -> Comments.article_id comment =. article_id)
      |> order_by (fun comment -> Comments.created_at comment) `Asc
      |> order_by (fun comment -> Comments.id comment) `Asc
      |> select Comments.projection))
;;

let%expect_test "comments by article SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite by_article);
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
    |}]
;;

module By_article_and_id = struct
  type t =
    { article_id : int64
    ; comment_id : Domain.Comment.Id.t
    }
  [@@deriving fields ~getters]

  let comment_id_value input = Domain.Comment.Id.to_int64 input.comment_id
end

let by_article_and_id =
  Statement.Portable.query_optional_exn (fun params ->
    let article_id =
      params.column Comments.article_id_column ~get:By_article_and_id.article_id
    in
    let comment_id =
      params.column Comments.id_column ~get:By_article_and_id.comment_id_value
    in
    Query.(
      from Comments.table
      |> where (fun comment ->
        Comments.id comment =. comment_id &&. (Comments.article_id comment =. article_id))
      |> limit_one
      |> select Comments.projection))
;;

let%expect_test "comment by article and ID SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite by_article_and_id);
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
    LIMIT 1
    |}]
;;

module Create_comment = struct
  type t =
    { article_id : int64
    ; author_id : Domain.User.Id.t
    ; body : string
    ; now : Ptime.t
    }
  [@@deriving fields ~getters]

  let author_id_value input = Domain.User.Id.to_int64 input.author_id
end

let create_comment =
  Statement.Portable.expect_one_exn (fun params ->
    let article_id =
      params.column Comments.article_id_column ~get:Create_comment.article_id
    in
    let author_id =
      params.column Comments.author_id_column ~get:Create_comment.author_id_value
    in
    let body = params.column Comments.body_column ~get:Create_comment.body in
    let now = params.column Comments.created_at_column ~get:Create_comment.now in
    Insert.(
      into Comments.table
      |> set_expr Comments.article_id_column article_id
      |> set_expr Comments.author_id_column author_id
      |> set_expr Comments.body_column body
      |> set_expr Comments.created_at_column now
      |> set_expr Comments.updated_at_column now
      |> returning Comments.projection))
;;

let%expect_test "create comment SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite create_comment);
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
    |}]
;;

let delete_comment =
  Statement.Portable.command_exn (fun params ->
    let id = params.column Comments.id_column ~get:Domain.Comment.Id.to_int64 in
    Delete.(from Comments.table |> where (fun row -> Comments.id row =. id) |> command))
;;

let%expect_test "delete comment SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite delete_comment);
  [%expect
    {|
    DELETE FROM "comments"
    WHERE
      ("id" = ?1)
    |}]
;;
