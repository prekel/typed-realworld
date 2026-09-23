open! Base
open Typed_sql
open Infix
module Domain = Realworld_domain.Domain
module Articles = Schema.Articles
module Tags = Schema.Tags
module Article_tags = Schema.Article_tags
module Favorites = Schema.Favorites
module Users = Schema.Users
module Follows = Schema.Follows

let filtered ~author ~tag ~favorited_by ~followed_by =
  Query.(
    from Articles.table
    |> where (fun article ->
      Expr.is_null author
      ||. (from Users.table
           |> where (fun user ->
             Users.id user
             =. Articles.author_id article
             &&. (Expr.to_nullable (Users.username user) =. author))
           |> exists)
      &&. (Expr.is_null tag
           ||. (from Article_tags.table
                |> inner_join Tags.table ~on:(fun article_tag tag_row ->
                  Article_tags.tag_id article_tag =. Tags.id tag_row)
                |> where (fun (article_tag, tag_row) ->
                  Article_tags.article_id article_tag
                  =. Articles.id article
                  &&. (Expr.to_nullable (Tags.name tag_row) =. tag))
                |> exists))
      &&. (Expr.is_null favorited_by
           ||. (from Favorites.table
                |> inner_join Users.table ~on:(fun favorite user ->
                  Favorites.user_id favorite =. Users.id user)
                |> where (fun (favorite, user) ->
                  Favorites.article_id favorite
                  =. Articles.id article
                  &&. (Expr.to_nullable (Users.username user) =. favorited_by))
                |> exists))
      &&. (Expr.is_null followed_by
           ||. (from Follows.table
                |> where (fun follow ->
                  Expr.to_nullable (Follows.follower_id follow)
                  =. followed_by
                  &&. (Follows.followed_id follow =. Articles.author_id article))
                |> exists))))
;;

module Page = struct
  type t =
    { filters : Domain.Article.filters
    ; followed_by : Domain.User.Id.t option
    ; page : Domain.Page.t
    }
  [@@deriving fields ~getters]

  let author input = Option.map input.filters.author ~f:Domain.User.Username.to_string
  let tag input = Option.map input.filters.tag ~f:Domain.Article.Tag.to_string

  let favorited_by input =
    Option.map input.filters.favorited_by ~f:Domain.User.Username.to_string
  ;;

  let followed_by_value input = Option.map input.followed_by ~f:Domain.User.Id.to_int64
  let limit input = Domain.Page.limit input.page
  let offset input = Domain.Page.offset input.page
end

let page =
  Statement.Portable.query_many_exn (fun params ->
    let author = params.expr (Db_type.option Db_type.text) ~get:Page.author in
    let tag = params.expr (Db_type.option Db_type.text) ~get:Page.tag in
    let favorited_by = params.expr (Db_type.option Db_type.text) ~get:Page.favorited_by in
    let followed_by =
      params.expr (Db_type.option Db_type.int64) ~get:Page.followed_by_value
    in
    let limit = params.non_negative_int ~name:"limit" ~get:Page.limit in
    let offset = params.non_negative_int ~name:"offset" ~get:Page.offset in
    filtered ~author ~tag ~favorited_by ~followed_by
    |> Query.order_by (fun article -> Articles.created_at article) `Desc
    |> Query.order_by (fun article -> Articles.id article) `Desc
    |> Query.limit_param limit
    |> Query.offset_param offset
    |> Query.select Articles.projection)
;;

let%expect_test "article page SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite page);
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
    |}]
;;

module Count = struct
  type t =
    { filters : Domain.Article.filters
    ; followed_by : Domain.User.Id.t option
    }
  [@@deriving fields ~getters]

  let author input = Option.map input.filters.author ~f:Domain.User.Username.to_string
  let tag input = Option.map input.filters.tag ~f:Domain.Article.Tag.to_string

  let favorited_by input =
    Option.map input.filters.favorited_by ~f:Domain.User.Username.to_string
  ;;

  let followed_by_value input = Option.map input.followed_by ~f:Domain.User.Id.to_int64
end

let count =
  Statement.Portable.query_one_exn (fun params ->
    let author = params.expr (Db_type.option Db_type.text) ~get:Count.author in
    let tag = params.expr (Db_type.option Db_type.text) ~get:Count.tag in
    let favorited_by =
      params.expr (Db_type.option Db_type.text) ~get:Count.favorited_by
    in
    let followed_by =
      params.expr (Db_type.option Db_type.int64) ~get:Count.followed_by_value
    in
    filtered ~author ~tag ~favorited_by ~followed_by
    |> Query.select_exactly_one (fun _ -> Projection.expr Expr.count_all))
;;

let%expect_test "article count SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite count);
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
    |}]
;;

let all : (unit, Articles.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Articles.table |> select Articles.projection))
;;

let%expect_test "all articles SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite all);
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
    |}]
;;

let all_tags : (unit, Tags.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Tags.table |> select Tags.projection))
;;

let%expect_test "all tags SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite all_tags);
  [%expect
    {|
    SELECT
      t0."id",
      t0."name"
    FROM "tags" AS t0
    |}]
;;

let all_article_tags : (unit, Article_tags.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Article_tags.table |> select Article_tags.projection))
;;

let%expect_test "all article tags SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite all_article_tags);
  [%expect
    {|
    SELECT
      t0."article_id",
      t0."tag_id",
      t0."position"
    FROM "article_tags" AS t0
    |}]
;;

let all_favorites : (unit, Favorites.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Favorites.table |> select Favorites.projection))
;;

let%expect_test "all favorites SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite all_favorites);
  [%expect
    {|
    SELECT
      t0."user_id",
      t0."article_id"
    FROM "favorites" AS t0
    |}]
;;

let article_tags_by_article_ids =
  Statement.Dynamic.Portable.query_many (fun article_ids ->
    Query.(
      from Article_tags.table
      |> where (fun article_tag ->
        Expr.in_ (Article_tags.article_id article_tag) article_ids)
      |> select Article_tags.projection))
;;

let%expect_test "article tags by article IDs SQL" =
  Stdlib.print_endline
    (Statement.sql_exn
       ~dialect:Dialect.Sqlite
       ~input:[ 101L; 102L ]
       article_tags_by_article_ids);
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
    |}]
;;

let tags_by_article_ids =
  Statement.Dynamic.Portable.query_many (fun article_ids ->
    Query.(
      from Tags.table
      |> where (fun tag ->
        in_subquery
          (Tags.id tag)
          (from Article_tags.table
           |> where (fun article_tag ->
             Expr.in_ (Article_tags.article_id article_tag) article_ids)
           |> select_scalar Article_tags.tag_id))
      |> select Tags.projection))
;;

let%expect_test "tags by article IDs SQL" =
  Stdlib.print_endline
    (Statement.sql_exn ~dialect:Dialect.Sqlite ~input:[ 101L; 102L ] tags_by_article_ids);
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
    |}]
;;

let favorites_by_article_ids =
  Statement.Dynamic.Portable.query_many (fun article_ids ->
    Query.(
      from Favorites.table
      |> where (fun favorite -> Expr.in_ (Favorites.article_id favorite) article_ids)
      |> select Favorites.projection))
;;

let%expect_test "favorites by article IDs SQL" =
  Stdlib.print_endline
    (Statement.sql_exn
       ~dialect:Dialect.Sqlite
       ~input:[ 101L; 102L ]
       favorites_by_article_ids);
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
    |}]
;;

let by_slug =
  Statement.Portable.query_optional_exn (fun params ->
    let slug = params.column Articles.slug_column ~get:Domain.Article.Slug.to_string in
    Query.(
      from Articles.table
      |> where (fun article -> Articles.slug article =. slug)
      |> limit_one
      |> select Articles.projection))
;;

let%expect_test "article by slug SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite by_slug);
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

module Create_article = struct
  type t =
    { author_id : Domain.User.Id.t
    ; slug : Domain.Article.Slug.t
    ; title : string
    ; description : string
    ; body : string
    ; now : Ptime.t
    }
  [@@deriving fields ~getters]

  let author_id_value input = Domain.User.Id.to_int64 input.author_id
  let slug_value input = Domain.Article.Slug.to_string input.slug
end

let create_article =
  Statement.Portable.expect_one_exn (fun params ->
    let author_id =
      params.column Articles.author_id_column ~get:Create_article.author_id_value
    in
    let slug = params.column Articles.slug_column ~get:Create_article.slug_value in
    let title = params.column Articles.title_column ~get:Create_article.title in
    let description =
      params.column Articles.description_column ~get:Create_article.description
    in
    let body = params.column Articles.body_column ~get:Create_article.body in
    let now = params.column Articles.created_at_column ~get:Create_article.now in
    Insert.(
      into Articles.table
      |> set_expr Articles.author_id_column author_id
      |> set_expr Articles.slug_column slug
      |> set_expr Articles.title_column title
      |> set_expr Articles.description_column description
      |> set_expr Articles.body_column body
      |> set_expr Articles.created_at_column now
      |> set_expr Articles.updated_at_column now
      |> returning Articles.projection))
;;

let%expect_test "create article SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite create_article);
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
    |}]
;;

module Update_article = struct
  type t =
    { id : int64
    ; slug : Domain.Article.Slug.t
    ; title : string
    ; description : string
    ; body : string
    ; now : Ptime.t
    }
  [@@deriving fields ~getters]

  let slug_value input = Domain.Article.Slug.to_string input.slug
end

let update_article =
  Statement.Portable.command_exn (fun params ->
    let id = params.column Articles.id_column ~get:Update_article.id in
    let slug = params.column Articles.slug_column ~get:Update_article.slug_value in
    let title = params.column Articles.title_column ~get:Update_article.title in
    let description =
      params.column Articles.description_column ~get:Update_article.description
    in
    let body = params.column Articles.body_column ~get:Update_article.body in
    let now = params.column Articles.updated_at_column ~get:Update_article.now in
    Update.(
      table Articles.table
      |> set_expr Articles.slug_column slug
      |> set_expr Articles.title_column title
      |> set_expr Articles.description_column description
      |> set_expr Articles.body_column body
      |> set_expr Articles.updated_at_column now
      |> where (fun article -> Articles.id article =. id)
      |> command))
;;

let%expect_test "update article SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite update_article);
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
    |}]
;;

let delete_article =
  Statement.Portable.command_exn (fun params ->
    let id = params.column Articles.id_column ~get:Fn.id in
    Delete.(
      from Articles.table |> where (fun article -> Articles.id article =. id) |> command))
;;

let%expect_test "delete article SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite delete_article);
  [%expect
    {|
    DELETE FROM "articles"
    WHERE
      ("id" = ?1)
    |}]
;;

let upsert_tag =
  Statement.Portable.expect_one_exn (fun params ->
    let name = params.column Tags.name_column ~get:Domain.Article.Tag.to_string in
    let target = Insert.Conflict_target.column Tags.name_column in
    Insert.(
      into Tags.table
      |> set_expr Tags.name_column name
      |> on_conflict target
      |> do_update (fun ~existing:_ ~excluded ->
        Conflict_update.(empty |> set_expr Tags.name_column (Tags.name excluded)))
      |> returning Tags.projection))
;;

let%expect_test "upsert tag SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite upsert_tag);
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
    |}]
;;

let clear_tags =
  Statement.Portable.command_exn (fun params ->
    let article_id = params.column Article_tags.article_id_column ~get:Fn.id in
    Delete.(
      from Article_tags.table
      |> where (fun tag -> Article_tags.article_id tag =. article_id)
      |> command))
;;

let%expect_test "clear article tags SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite clear_tags);
  [%expect
    {|
    DELETE FROM "article_tags"
    WHERE
      ("article_id" = ?1)
    |}]
;;

module Attach_tag = struct
  type t =
    { article_id : int64
    ; tag_id : int64
    ; position : int
    }
  [@@deriving fields ~getters]

  let position_value input = Int64.of_int input.position
end

let attach_tag =
  Statement.Portable.command_exn (fun params ->
    let article_id =
      params.column Article_tags.article_id_column ~get:Attach_tag.article_id
    in
    let tag_id = params.column Article_tags.tag_id_column ~get:Attach_tag.tag_id in
    let position =
      params.column Article_tags.position_column ~get:Attach_tag.position_value
    in
    Insert.(
      into Article_tags.table
      |> set_expr Article_tags.article_id_column article_id
      |> set_expr Article_tags.tag_id_column tag_id
      |> set_expr Article_tags.position_column position
      |> command))
;;

let%expect_test "attach tag SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite attach_tag);
  [%expect
    {|
    INSERT INTO "article_tags" (
      "article_id",
      "tag_id",
      "position"
    )
    VALUES
      (?1, ?2, ?3)
    |}]
;;

module Add_favorite = struct
  type t =
    { user_id : Domain.User.Id.t
    ; article_id : int64
    }
  [@@deriving fields ~getters]

  let user_id_value input = Domain.User.Id.to_int64 input.user_id
end

let add_favorite =
  Statement.Portable.command_exn (fun params ->
    let user_id =
      params.column Favorites.user_id_column ~get:Add_favorite.user_id_value
    in
    let article_id =
      params.column Favorites.article_id_column ~get:Add_favorite.article_id
    in
    Insert.(
      into Favorites.table
      |> set_expr Favorites.user_id_column user_id
      |> set_expr Favorites.article_id_column article_id
      |> on_conflict_do_nothing
      |> command))
;;

let%expect_test "add favorite SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite add_favorite);
  [%expect
    {|
    INSERT INTO "favorites" (
      "user_id",
      "article_id"
    )
    VALUES
      (?1, ?2)
    ON CONFLICT DO NOTHING
    |}]
;;

let remove_favorite =
  Statement.Portable.command_exn (fun params ->
    let user_id =
      params.column Favorites.user_id_column ~get:Add_favorite.user_id_value
    in
    let article_id =
      params.column Favorites.article_id_column ~get:Add_favorite.article_id
    in
    Delete.(
      from Favorites.table
      |> where (fun favorite ->
        Favorites.user_id favorite
        =. user_id
        &&. (Favorites.article_id favorite =. article_id))
      |> command))
;;

let%expect_test "remove favorite SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite remove_favorite);
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
