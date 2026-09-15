open! Base
open Typed_sql
open Infix
module Articles = Schema.Articles
module Comments = Schema.Comments

let article_by_slug slug =
  Query.(
    from Articles.table
    |> where (fun article -> Articles.slug article =$ slug)
    |> select Articles.projection)
;;

let all () = Query.(from Comments.table |> select Comments.projection)

let by_article article_id =
  Query.(
    from Comments.table
    |> where (fun comment -> Comments.article_id comment =$ article_id)
    |> order_by (fun comment -> Comments.created_at comment) `Asc
    |> order_by (fun comment -> Comments.id comment) `Asc
    |> select Comments.projection)
;;

let by_article_and_id ~article_id ~comment_id =
  Query.(
    from Comments.table
    |> where (fun comment ->
      Comments.id comment
      =$ Int64.of_int comment_id
      &&. (Comments.article_id comment =$ article_id))
    |> select Comments.projection)
;;

let insert ~article_id ~author_id ~body ~now =
  Insert.(
    into Comments.table
    |> set Comments.article_id_column article_id
    |> set Comments.author_id_column (Int64.of_int author_id)
    |> set Comments.body_column body
    |> set Comments.created_at_column now
    |> set Comments.updated_at_column now
    |> returning Comments.projection)
;;

let delete id =
  Delete.(from Comments.table |> where (fun row -> Comments.id row =$ id) |> command)
;;
