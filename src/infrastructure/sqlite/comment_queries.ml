open! Base
open Typed_sql
open Infix
module Domain = Realworld_domain.Domain
module Articles = Schema.Articles
module Comments = Schema.Comments

module Article_by_slug = struct
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

module All = struct
  module Input = struct
    type t = unit
  end

  let statement =
    Statement.Portable.query_many_exn (fun (_ : (Input.t, _) Statement.parameters) ->
      Query.(from Comments.table |> select Comments.projection))
  ;;
end

module By_article = struct
  module Input = struct
    type t = int64
  end

  let statement =
    Statement.Portable.query_many_exn (fun params ->
      let article_id = params.column Comments.article_id_column ~get:Fn.id in
      Query.(
        from Comments.table
        |> where (fun comment -> Comments.article_id comment =. article_id)
        |> order_by (fun comment -> Comments.created_at comment) `Asc
        |> order_by (fun comment -> Comments.id comment) `Asc
        |> select Comments.projection))
  ;;
end

module By_article_and_id = struct
  module Input = struct
    type t =
      { article_id : int64
      ; comment_id : Domain.Comment.Id.t
      }
    [@@deriving fields ~getters]

    let comment_id_value input = Domain.Comment.Id.to_int64 input.comment_id
  end

  let statement =
    Statement.Portable.query_optional_exn (fun params ->
      let article_id = params.column Comments.article_id_column ~get:Input.article_id in
      let comment_id = params.column Comments.id_column ~get:Input.comment_id_value in
      Query.(
        from Comments.table
        |> where (fun comment ->
          Comments.id comment =. comment_id &&. (Comments.article_id comment =. article_id))
        |> select Comments.projection))
  ;;
end

module Create_comment = struct
  module Input = struct
    type t =
      { article_id : int64
      ; author_id : Domain.User.Id.t
      ; body : string
      ; now : Ptime.t
      }
    [@@deriving fields ~getters]

    let author_id_value input = Domain.User.Id.to_int64 input.author_id
  end

  let statement =
    Statement.Portable.query_one_exn (fun params ->
      let article_id = params.column Comments.article_id_column ~get:Input.article_id in
      let author_id =
        params.column Comments.author_id_column ~get:Input.author_id_value
      in
      let body = params.column Comments.body_column ~get:Input.body in
      let now = params.column Comments.created_at_column ~get:Input.now in
      Insert.(
        into Comments.table
        |> set_expr Comments.article_id_column article_id
        |> set_expr Comments.author_id_column author_id
        |> set_expr Comments.body_column body
        |> set_expr Comments.created_at_column now
        |> set_expr Comments.updated_at_column now
        |> returning Comments.projection))
  ;;
end

module Delete_comment = struct
  module Input = struct
    type t = Domain.Comment.Id.t
  end

  let statement =
    Statement.Portable.command_exn (fun params ->
      let id = params.column Comments.id_column ~get:Domain.Comment.Id.to_int64 in
      Delete.(from Comments.table |> where (fun row -> Comments.id row =. id) |> command))
  ;;
end
