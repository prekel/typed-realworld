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

let filtered ~(filters : Domain.Article.filters) ~followed_by =
  Query.(
    from Articles.table
    |> where_opt filters.author ~f:(fun article username ->
      from Users.table
      |> where (fun user ->
        Users.id user =. Articles.author_id article &&. (Users.username user =$ username))
      |> exists)
    |> where_opt filters.tag ~f:(fun article name ->
      from Article_tags.table
      |> inner_join Tags.table ~on:(fun article_tag tag ->
        Article_tags.tag_id article_tag =. Tags.id tag)
      |> where (fun (article_tag, tag) ->
        Article_tags.article_id article_tag
        =. Articles.id article
        &&. (Tags.name tag =$ name))
      |> exists)
    |> where_opt filters.favorited_by ~f:(fun article username ->
      from Favorites.table
      |> inner_join Users.table ~on:(fun favorite user ->
        Favorites.user_id favorite =. Users.id user)
      |> where (fun (favorite, user) ->
        Favorites.article_id favorite
        =. Articles.id article
        &&. (Users.username user =$ username))
      |> exists)
    |> where_opt followed_by ~f:(fun article user_id ->
      from Follows.table
      |> where (fun follow ->
        Follows.follower_id follow
        =$ Int64.of_int user_id
        &&. (Follows.followed_id follow =. Articles.author_id article))
      |> exists))
;;

let page ~filters ~followed_by ~(page : Domain.Page.t) =
  filtered ~filters ~followed_by
  |> Query.order_by (fun article -> Articles.created_at article) `Desc
  |> Query.order_by (fun article -> Articles.id article) `Desc
  |> Query.limit page.limit
  |> Query.offset page.offset
  |> Query.select Articles.projection
;;

let count ~filters ~followed_by =
  filtered ~filters ~followed_by |> Query.select (fun _ -> Projection.expr Expr.count_all)
;;

let all () = Query.(from Articles.table |> select Articles.projection)
let all_tags () = Query.(from Tags.table |> select Tags.projection)

let all_article_tags () =
  Query.(from Article_tags.table |> select Article_tags.projection)
;;

let all_favorites () = Query.(from Favorites.table |> select Favorites.projection)

let article_tags_by_article_ids article_ids =
  Query.(
    from Article_tags.table
    |> where (fun article_tag ->
      Expr.in_ (Article_tags.article_id article_tag) article_ids)
    |> select Article_tags.projection)
;;

let tags_by_article_ids article_ids =
  Query.(
    from Tags.table
    |> where (fun tag ->
      in_subquery
        (Tags.id tag)
        (from Article_tags.table
         |> where (fun article_tag ->
           Expr.in_ (Article_tags.article_id article_tag) article_ids)
         |> select_scalar Article_tags.tag_id))
    |> select Tags.projection)
;;

let favorites_by_article_ids article_ids =
  Query.(
    from Favorites.table
    |> where (fun favorite -> Expr.in_ (Favorites.article_id favorite) article_ids)
    |> select Favorites.projection)
;;

let by_slug slug =
  Query.(
    from Articles.table
    |> where (fun article -> Articles.slug article =$ slug)
    |> select Articles.projection)
;;

let tag_by_name name =
  Query.(
    from Tags.table |> where (fun tag -> Tags.name tag =$ name) |> select Tags.projection)
;;

let insert ~author_id ~slug ~now (article : Domain.Article.create) =
  Insert.(
    into Articles.table
    |> set Articles.author_id_column (Int64.of_int author_id)
    |> set Articles.slug_column slug
    |> set Articles.title_column article.title
    |> set Articles.description_column article.description
    |> set Articles.body_column article.body
    |> set Articles.created_at_column now
    |> set Articles.updated_at_column now
    |> returning Articles.projection)
;;

let update ~id ~slug ~title ~description ~body ~now =
  Update.(
    table Articles.table
    |> set Articles.slug_column slug
    |> set Articles.title_column title
    |> set Articles.description_column description
    |> set Articles.body_column body
    |> set Articles.updated_at_column now
    |> where (fun article -> Articles.id article =$ id)
    |> command)
;;

let delete id =
  Delete.(
    from Articles.table |> where (fun article -> Articles.id article =$ id) |> command)
;;

let insert_tag name =
  Insert.(into Tags.table |> set Tags.name_column name |> returning Tags.projection)
;;

let clear_tags article_id =
  Delete.(
    from Article_tags.table
    |> where (fun tag -> Article_tags.article_id tag =$ article_id)
    |> command)
;;

let attach_tag ~article_id ~tag_id ~position =
  Insert.(
    into Article_tags.table
    |> set Article_tags.article_id_column article_id
    |> set Article_tags.tag_id_column tag_id
    |> set Article_tags.position_column (Int64.of_int position)
    |> command)
;;

let add_favorite ~user_id ~article_id =
  Insert.(
    into Favorites.table
    |> set Favorites.user_id_column (Int64.of_int user_id)
    |> set Favorites.article_id_column article_id
    |> on_conflict_do_nothing
    |> command)
;;

let remove_favorite ~user_id ~article_id =
  Delete.(
    from Favorites.table
    |> where (fun favorite ->
      Favorites.user_id favorite
      =$ Int64.of_int user_id
      &&. (Favorites.article_id favorite =$ article_id))
    |> command)
;;
