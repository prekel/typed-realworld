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

type article_tag =
  { article_id : int64
  ; position : int64
  ; name : Domain.Article.Tag.t
  }

let read_projection ~viewer_id (article, author) =
  let following =
    Query.(
      from Follows.table
      |> where (fun follow ->
        Expr.to_nullable (Follows.follower_id follow)
        =. viewer_id
        &&. (Follows.followed_id follow =. Users.id author))
      |> limit_one
      |> select_scalar Follows.followed_id)
    |> Expr.scalar_subquery
  in
  let favorited =
    Query.(
      from Favorites.table
      |> where (fun favorite ->
        Expr.to_nullable (Favorites.user_id favorite)
        =. viewer_id
        &&. (Favorites.article_id favorite =. Articles.id article))
      |> limit_one
      |> select_scalar Favorites.user_id)
    |> Expr.scalar_subquery
  in
  let favorites_count =
    Query.(
      from Favorites.table
      |> where (fun favorite -> Favorites.article_id favorite =. Articles.id article)
      |> select_scalar (fun _ -> Expr.count_all))
    |> Expr.scalar_subquery
  in
  let open Projection.Let_syntax in
  let%map article = Articles.projection article
  and username = Projection.expr (Users.username author)
  and bio = Projection.expr (Users.bio author)
  and image = Projection.expr (Users.image author)
  and following = Projection.expr following
  and favorited = Projection.expr favorited
  and favorites_count = Projection.expr favorites_count in
  Domain.Article.
    { id = Id.of_int64_exn article.id
    ; slug = Slug.of_string_exn article.slug
    ; title = article.title
    ; description = article.description
    ; body = article.body
    ; tag_list = []
    ; created_at = article.created_at
    ; updated_at = article.updated_at
    ; favorited = Option.is_some favorited
    ; favorites_count = Option.value favorites_count ~default:0L |> Int64.to_int_exn
    ; author =
        Domain.Profile.
          { username = Domain.User.Username.of_string_exn username
          ; bio
          ; image
          ; following = Option.is_some following
          }
    }
;;

let filtered ~author ~tag ~favorited_by ~followed_by =
  Query.(
    from Articles.table
    |> where_optional_param author ~f:(fun article author ->
      from Users.table
      |> where (fun user ->
        Users.id user
        =. Articles.author_id article
        &&. (Expr.to_nullable (Users.username user) =. author))
      |> exists)
    |> where_optional_param tag ~f:(fun article tag ->
      from Article_tags.table
      |> inner_join Tags.table ~on:(fun article_tag tag_row ->
        Article_tags.tag_id article_tag =. Tags.id tag_row)
      |> where (fun (article_tag, tag_row) ->
        Article_tags.article_id article_tag
        =. Articles.id article
        &&. (Expr.to_nullable (Tags.name tag_row) =. tag))
      |> exists)
    |> where_optional_param favorited_by ~f:(fun article favorited_by ->
      from Favorites.table
      |> inner_join Users.table ~on:(fun favorite user ->
        Favorites.user_id favorite =. Users.id user)
      |> where (fun (favorite, user) ->
        Favorites.article_id favorite
        =. Articles.id article
        &&. (Expr.to_nullable (Users.username user) =. favorited_by))
      |> exists)
    |> where_optional_param followed_by ~f:(fun article followed_by ->
      from Follows.table
      |> where (fun follow ->
        Expr.to_nullable (Follows.follower_id follow)
        =. followed_by
        &&. (Follows.followed_id follow =. Articles.author_id article))
      |> exists))
;;

module Page = struct
  type t =
    { filters : Domain.Article.filters
    ; viewer_id : Domain.User.Id.t option
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
  let viewer_id_value input = Option.map input.viewer_id ~f:Domain.User.Id.to_int64
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
    let viewer_id =
      params.expr (Db_type.option Db_type.int64) ~get:Page.viewer_id_value
    in
    let limit = params.non_negative_int ~name:"limit" ~get:Page.limit in
    let offset = params.non_negative_int ~name:"offset" ~get:Page.offset in
    filtered ~author ~tag ~favorited_by ~followed_by
    |> Query.inner_join Users.table ~on:(fun article user ->
      Articles.author_id article =. Users.id user)
    |> Query.order_by (fun (article, _) -> Articles.created_at article) `Desc
    |> Query.order_by (fun (article, _) -> Articles.id article) `Desc
    |> Query.limit_param limit
    |> Query.offset_param offset
    |> Query.select (read_projection ~viewer_id))
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
      t0."updated_at",
      t1."username",
      t1."bio",
      t1."image",
      (
        SELECT
          t2."followed_id"
        FROM "follows" AS t2
        WHERE
          (
            (t2."follower_id" = ?1)
            AND (t2."followed_id" = t1."id")
          )
        LIMIT 1
      ),
      (
        SELECT
          t2."user_id"
        FROM "favorites" AS t2
        WHERE
          (
            (t2."user_id" = ?1)
            AND (t2."article_id" = t0."id")
          )
        LIMIT 1
      ),
      (
        SELECT
          COUNT(*)
        FROM "favorites" AS t2
        WHERE
          (t2."article_id" = t0."id")
      )
    FROM "articles" AS t0
    INNER JOIN "users" AS t1
      ON (t0."author_id" = t1."id")
    WHERE
      (
        (
          (?2 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "users" AS t2
            WHERE
              (
                (t2."id" = t0."author_id")
                AND (t2."username" = ?2)
              )
          ))
        )
        AND (
          (?3 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "article_tags" AS t2
            INNER JOIN "tags" AS t3
              ON (t2."tag_id" = t3."id")
            WHERE
              (
                (t2."article_id" = t0."id")
                AND (t3."name" = ?3)
              )
          ))
        )
        AND (
          (?4 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "favorites" AS t2
            INNER JOIN "users" AS t3
              ON (t2."user_id" = t3."id")
            WHERE
              (
                (t2."article_id" = t0."id")
                AND (t3."username" = ?4)
              )
          ))
        )
        AND (
          (?5 IS NULL)
          OR (EXISTS (
            SELECT
              1
            FROM "follows" AS t2
            WHERE
              (
                (t2."follower_id" = ?5)
                AND (t2."followed_id" = t0."author_id")
              )
          ))
        )
      )
    ORDER BY
      t0."created_at" DESC,
      t0."id" DESC
    LIMIT ?6
    OFFSET ?7
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
    Query.Aggregate.(
      from Articles.table
      |> where_optional_param author ~f:(fun article author ->
        Query.(
          from Users.table
          |> where (fun user ->
            Users.id user
            =. Articles.author_id article
            &&. (Expr.to_nullable (Users.username user) =. author))
          |> exists))
      |> where_optional_param tag ~f:(fun article tag ->
        Query.(
          from Article_tags.table
          |> inner_join Tags.table ~on:(fun article_tag tag_row ->
            Article_tags.tag_id article_tag =. Tags.id tag_row)
          |> where (fun (article_tag, tag_row) ->
            Article_tags.article_id article_tag
            =. Articles.id article
            &&. (Expr.to_nullable (Tags.name tag_row) =. tag))
          |> exists))
      |> where_optional_param favorited_by ~f:(fun article favorited_by ->
        Query.(
          from Favorites.table
          |> inner_join Users.table ~on:(fun favorite user ->
            Favorites.user_id favorite =. Users.id user)
          |> where (fun (favorite, user) ->
            Favorites.article_id favorite
            =. Articles.id article
            &&. (Expr.to_nullable (Users.username user) =. favorited_by))
          |> exists))
      |> where_optional_param followed_by ~f:(fun article followed_by ->
        Query.(
          from Follows.table
          |> where (fun follow ->
            Expr.to_nullable (Follows.follower_id follow)
            =. followed_by
            &&. (Follows.followed_id follow =. Articles.author_id article))
          |> exists))
      |> Query.aggregate_one (fun _ -> Aggregate_projection.count_all)))
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

let article_tags_by_article_ids =
  Statement.Dynamic.Portable.query_many (fun article_ids ->
    Query.(
      from Article_tags.table
      |> inner_join Tags.table ~on:(fun article_tag tag ->
        Article_tags.tag_id article_tag =. Tags.id tag)
      |> where (fun article_tag ->
        Expr.in_ (Article_tags.article_id (fst article_tag)) article_ids)
      |> order_by (fun (article_tag, _) -> Article_tags.article_id article_tag) `Asc
      |> order_by (fun (article_tag, _) -> Article_tags.position article_tag) `Asc
      |> select (fun (article_tag, tag) ->
        let open Projection.Let_syntax in
        let%map article_id = Projection.expr (Article_tags.article_id article_tag)
        and position = Projection.expr (Article_tags.position article_tag)
        and name = Projection.expr (Tags.name tag) in
        { article_id; position; name = Domain.Article.Tag.of_string_exn name })))
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
      t0."position",
      t1."name"
    FROM "article_tags" AS t0
    INNER JOIN "tags" AS t1
      ON (t0."tag_id" = t1."id")
    WHERE
      (t0."article_id" IN (
        ?1,
        ?2
      ))
    ORDER BY
      t0."article_id" ASC,
      t0."position" ASC
    |}]
;;

module Read_by_slug = struct
  type t =
    { viewer_id : Domain.User.Id.t option
    ; slug : Domain.Article.Slug.t
    }
  [@@deriving fields ~getters]

  let viewer_id_value input = Option.map input.viewer_id ~f:Domain.User.Id.to_int64
  let slug_value input = Domain.Article.Slug.to_string input.slug
end

let read_by_slug =
  Statement.Portable.query_optional_exn (fun params ->
    let viewer_id =
      params.expr (Db_type.option Db_type.int64) ~get:Read_by_slug.viewer_id_value
    in
    let slug = params.column Articles.slug_column ~get:Read_by_slug.slug_value in
    Query.(
      from Articles.table
      |> inner_join Users.table ~on:(fun article user ->
        Articles.author_id article =. Users.id user)
      |> where (fun (article, _) -> Articles.slug article =. slug)
      |> limit_one
      |> select (read_projection ~viewer_id)))
;;

let%expect_test "read article by slug SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite read_by_slug);
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
      t0."updated_at",
      t1."username",
      t1."bio",
      t1."image",
      (
        SELECT
          t2."followed_id"
        FROM "follows" AS t2
        WHERE
          (
            (t2."follower_id" = ?1)
            AND (t2."followed_id" = t1."id")
          )
        LIMIT 1
      ),
      (
        SELECT
          t2."user_id"
        FROM "favorites" AS t2
        WHERE
          (
            (t2."user_id" = ?1)
            AND (t2."article_id" = t0."id")
          )
        LIMIT 1
      ),
      (
        SELECT
          COUNT(*)
        FROM "favorites" AS t2
        WHERE
          (t2."article_id" = t0."id")
      )
    FROM "articles" AS t0
    INNER JOIN "users" AS t1
      ON (t0."author_id" = t1."id")
    WHERE
      (t0."slug" = ?2)
    LIMIT 1
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
    ; author_id : Domain.User.Id.t
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

let update_article =
  Statement.Portable.expect_optional_exn (fun params ->
    let id = params.column Articles.id_column ~get:Update_article.id in
    let author_id =
      params.column Articles.author_id_column ~get:Update_article.author_id_value
    in
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
      |> where (fun article ->
        Articles.id article =. id &&. (Articles.author_id article =. author_id))
      |> returning (fun article -> Projection.expr (Articles.id article))))
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
      (
        ("id" = ?6)
        AND ("author_id" = ?7)
      )
    RETURNING
      "id"
    |}]
;;

module Delete_article = struct
  type t =
    { id : int64
    ; author_id : Domain.User.Id.t
    }
  [@@deriving fields ~getters]

  let author_id_value input = Domain.User.Id.to_int64 input.author_id
end

let delete_article =
  Statement.Portable.expect_optional_exn (fun params ->
    let id = params.column Articles.id_column ~get:Delete_article.id in
    let author_id =
      params.column Articles.author_id_column ~get:Delete_article.author_id_value
    in
    Delete.(
      from Articles.table
      |> where (fun article ->
        Articles.id article =. id &&. (Articles.author_id article =. author_id))
      |> returning (fun article -> Projection.expr (Articles.id article))))
;;

let%expect_test "delete article SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite delete_article);
  [%expect
    {|
    DELETE FROM "articles"
    WHERE
      (
        ("id" = ?1)
        AND ("author_id" = ?2)
      )
    RETURNING
      "id"
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
