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
  module Input = struct
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

  let statement =
    Statement.Portable.query_many_exn (fun params ->
      let author = params.expr (Db_type.option Db_type.text) ~get:Input.author in
      let tag = params.expr (Db_type.option Db_type.text) ~get:Input.tag in
      let favorited_by =
        params.expr (Db_type.option Db_type.text) ~get:Input.favorited_by
      in
      let followed_by =
        params.expr (Db_type.option Db_type.int64) ~get:Input.followed_by_value
      in
      let limit = params.non_negative_int ~name:"limit" ~get:Input.limit in
      let offset = params.non_negative_int ~name:"offset" ~get:Input.offset in
      filtered ~author ~tag ~favorited_by ~followed_by
      |> Query.order_by (fun article -> Articles.created_at article) `Desc
      |> Query.order_by (fun article -> Articles.id article) `Desc
      |> Query.limit_param limit
      |> Query.offset_param offset
      |> Query.select Articles.projection)
  ;;
end

module Count = struct
  module Input = struct
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

  let statement =
    Statement.Portable.query_one_exn (fun params ->
      let author = params.expr (Db_type.option Db_type.text) ~get:Input.author in
      let tag = params.expr (Db_type.option Db_type.text) ~get:Input.tag in
      let favorited_by =
        params.expr (Db_type.option Db_type.text) ~get:Input.favorited_by
      in
      let followed_by =
        params.expr (Db_type.option Db_type.int64) ~get:Input.followed_by_value
      in
      filtered ~author ~tag ~favorited_by ~followed_by
      |> Query.select (fun _ -> Projection.expr Expr.count_all))
  ;;
end

module All = struct
  module Input = struct
    type t = unit
  end

  let statement =
    Statement.Portable.query_many_exn (fun (_ : (Input.t, _) Statement.parameters) ->
      Query.(from Articles.table |> select Articles.projection))
  ;;
end

module All_tags = struct
  module Input = struct
    type t = unit
  end

  let statement =
    Statement.Portable.query_many_exn (fun (_ : (Input.t, _) Statement.parameters) ->
      Query.(from Tags.table |> select Tags.projection))
  ;;
end

module All_article_tags = struct
  module Input = struct
    type t = unit
  end

  let statement =
    Statement.Portable.query_many_exn (fun (_ : (Input.t, _) Statement.parameters) ->
      Query.(from Article_tags.table |> select Article_tags.projection))
  ;;
end

module All_favorites = struct
  module Input = struct
    type t = unit
  end

  let statement =
    Statement.Portable.query_many_exn (fun (_ : (Input.t, _) Statement.parameters) ->
      Query.(from Favorites.table |> select Favorites.projection))
  ;;
end

module Article_tags_by_article_ids = struct
  module Input = struct
    type t = int64 list
  end

  let statement =
    Statement.Dynamic.Portable.query_many (fun article_ids ->
      Query.(
        from Article_tags.table
        |> where (fun article_tag ->
          Expr.in_ (Article_tags.article_id article_tag) article_ids)
        |> select Article_tags.projection))
  ;;
end

module Tags_by_article_ids = struct
  module Input = struct
    type t = int64 list
  end

  let statement =
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
end

module Favorites_by_article_ids = struct
  module Input = struct
    type t = int64 list
  end

  let statement =
    Statement.Dynamic.Portable.query_many (fun article_ids ->
      Query.(
        from Favorites.table
        |> where (fun favorite -> Expr.in_ (Favorites.article_id favorite) article_ids)
        |> select Favorites.projection))
  ;;
end

module By_slug = struct
  module Input = struct
    type t = Domain.Article.Slug.t
  end

  let statement =
    Statement.Portable.query_optional_exn (fun params ->
      let slug = params.column Articles.slug_column ~get:Domain.Article.Slug.to_string in
      Query.(
        from Articles.table
        |> where (fun article -> Articles.slug article =. slug)
        |> select Articles.projection))
  ;;
end

module Create_article = struct
  module Input = struct
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

  let statement =
    Statement.Portable.query_one_exn (fun params ->
      let author_id =
        params.column Articles.author_id_column ~get:Input.author_id_value
      in
      let slug = params.column Articles.slug_column ~get:Input.slug_value in
      let title = params.column Articles.title_column ~get:Input.title in
      let description =
        params.column Articles.description_column ~get:Input.description
      in
      let body = params.column Articles.body_column ~get:Input.body in
      let now = params.column Articles.created_at_column ~get:Input.now in
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
end

module Update_article = struct
  module Input = struct
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

  let statement =
    Statement.Portable.command_exn (fun params ->
      let id = params.column Articles.id_column ~get:Input.id in
      let slug = params.column Articles.slug_column ~get:Input.slug_value in
      let title = params.column Articles.title_column ~get:Input.title in
      let description =
        params.column Articles.description_column ~get:Input.description
      in
      let body = params.column Articles.body_column ~get:Input.body in
      let now = params.column Articles.updated_at_column ~get:Input.now in
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
end

module Delete_article = struct
  module Input = struct
    type t = int64
  end

  let statement =
    Statement.Portable.command_exn (fun params ->
      let id = params.column Articles.id_column ~get:Fn.id in
      Delete.(
        from Articles.table |> where (fun article -> Articles.id article =. id) |> command))
  ;;
end

module Upsert_tag = struct
  module Input = struct
    type t = Domain.Article.Tag.t
  end

  let statement =
    Statement.Portable.query_one_exn (fun params ->
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
end

module Clear_tags = struct
  module Input = struct
    type t = int64
  end

  let statement =
    Statement.Portable.command_exn (fun params ->
      let article_id = params.column Article_tags.article_id_column ~get:Fn.id in
      Delete.(
        from Article_tags.table
        |> where (fun tag -> Article_tags.article_id tag =. article_id)
        |> command))
  ;;
end

module Attach_tag = struct
  module Input = struct
    type t =
      { article_id : int64
      ; tag_id : int64
      ; position : int
      }
    [@@deriving fields ~getters]

    let position_value input = Int64.of_int input.position
  end

  let statement =
    Statement.Portable.command_exn (fun params ->
      let article_id =
        params.column Article_tags.article_id_column ~get:Input.article_id
      in
      let tag_id = params.column Article_tags.tag_id_column ~get:Input.tag_id in
      let position =
        params.column Article_tags.position_column ~get:Input.position_value
      in
      Insert.(
        into Article_tags.table
        |> set_expr Article_tags.article_id_column article_id
        |> set_expr Article_tags.tag_id_column tag_id
        |> set_expr Article_tags.position_column position
        |> command))
  ;;
end

module Add_favorite = struct
  module Input = struct
    type t =
      { user_id : Domain.User.Id.t
      ; article_id : int64
      }
    [@@deriving fields ~getters]

    let user_id_value input = Domain.User.Id.to_int64 input.user_id
  end

  let statement =
    Statement.Portable.command_exn (fun params ->
      let user_id = params.column Favorites.user_id_column ~get:Input.user_id_value in
      let article_id = params.column Favorites.article_id_column ~get:Input.article_id in
      Insert.(
        into Favorites.table
        |> set_expr Favorites.user_id_column user_id
        |> set_expr Favorites.article_id_column article_id
        |> on_conflict_do_nothing
        |> command))
  ;;
end

module Remove_favorite = struct
  module Input = Add_favorite.Input

  let statement =
    Statement.Portable.command_exn (fun params ->
      let user_id = params.column Favorites.user_id_column ~get:Input.user_id_value in
      let article_id = params.column Favorites.article_id_column ~get:Input.article_id in
      Delete.(
        from Favorites.table
        |> where (fun favorite ->
          Favorites.user_id favorite
          =. user_id
          &&. (Favorites.article_id favorite =. article_id))
        |> command))
  ;;
end
