open! Base
open Typed_sql
open Infix
open Lwt.Let_syntax
module Application = Realworld_application
module Domain = Realworld_domain.Domain
module Persistence_error = Application.Persistence_error
module Schema = Schema
module Users = Schema.Users
module Articles = Schema.Articles
module Tags = Schema.Tags
module Article_tags = Schema.Article_tags
module Favorites = Schema.Favorites
module Follows = Schema.Follows
module Comments = Schema.Comments
module Adapter = Typed_sql_caqti_lwt

type 'a io = 'a Lwt.t
type connection = Caqti_lwt.connection

let persistence error = Persistence_error.of_string (Adapter.error_to_string error)

let run ~conn statement input =
  let%map result = Adapter.run ~conn statement input in
  Result.map_error result ~f:persistence
;;

let run_unit ~conn statement input =
  let%map result = run ~conn statement input in
  Result.map result ~f:(fun _ -> ())
;;

let user_of_row (row : Users.t) =
  Domain.User.
    { id = Id.of_int64_exn row.id
    ; email = row.email
    ; username = Username.of_string_exn row.username
    ; password_hash = row.password_hash
    ; bio = row.bio
    ; image = row.image
    }
;;

let profile_of_user ~viewer_id ~follows user =
  let following =
    Option.value_map viewer_id ~default:false ~f:(fun viewer_id ->
      List.exists follows ~f:(fun follow ->
        Int64.equal follow.Follows.follower_id (Domain.User.Id.to_int64 viewer_id)
        && Int64.equal follow.Follows.followed_id user.Users.id))
  in
  Domain.Profile.
    { username = Domain.User.Username.of_string_exn user.username
    ; bio = user.bio
    ; image = user.image
    ; following
    }
;;

let users ~conn = run ~conn User_queries.all_rows ()
let follows ~conn = run ~conn User_queries.all_follows ()
let tags ~conn = run ~conn Article_queries.all_tags ()
let comments ~conn = run ~conn Comment_queries.all ()
let find_user_row rows id = List.find rows ~f:(fun row -> Int64.equal row.Users.id id)

let find_article_row rows slug =
  List.find rows ~f:(fun row ->
    String.equal row.Articles.slug (Domain.Article.Slug.to_string slug))
;;

let tag_names ~article_id ~tags:all_tags ~article_tags:all_article_tags =
  all_article_tags
  |> List.filter ~f:(fun row -> Int64.equal row.Article_tags.article_id article_id)
  |> List.sort ~compare:(fun left right ->
    Int64.compare left.Article_tags.position right.Article_tags.position)
  |> List.filter_map ~f:(fun article_tag ->
    List.find all_tags ~f:(fun tag ->
      Int64.equal tag.Tags.id article_tag.Article_tags.tag_id)
    |> Option.map ~f:(fun tag -> Domain.Article.Tag.of_string_exn tag.Tags.name))
;;

let article_of_row
      ~viewer_id
      ~all_users
      ~all_follows
      ~all_tags
      ~all_article_tags
      ~all_favorites
      (row : Articles.t)
  =
  match find_user_row all_users row.author_id with
  | None -> Error (Persistence_error.of_string "article author is missing")
  | Some author ->
    let favorited =
      Option.value_map viewer_id ~default:false ~f:(fun viewer_id ->
        List.exists all_favorites ~f:(fun favorite ->
          Int64.equal favorite.Favorites.user_id (Domain.User.Id.to_int64 viewer_id)
          && Int64.equal favorite.Favorites.article_id row.id))
    in
    let favorites_count =
      List.count all_favorites ~f:(fun favorite ->
        Int64.equal favorite.Favorites.article_id row.id)
    in
    Ok
      Domain.Article.
        { id = Id.of_int64_exn row.id
        ; slug = Slug.of_string_exn row.slug
        ; title = row.title
        ; description = row.description
        ; body = row.body
        ; tag_list =
            tag_names ~article_id:row.id ~tags:all_tags ~article_tags:all_article_tags
        ; created_at = row.created_at
        ; updated_at = row.updated_at
        ; favorited
        ; favorites_count
        ; author = profile_of_user ~viewer_id ~follows:all_follows author
        }
;;

let hydrate_articles ~conn ~viewer_id rows =
  let article_ids = List.map rows ~f:(fun row -> row.Articles.id) in
  let author_ids =
    List.map rows ~f:(fun row -> row.Articles.author_id)
    |> List.dedup_and_sort ~compare:Int64.compare
  in
  let%bind found_users = run ~conn User_queries.rows_by_ids author_ids in
  match found_users with
  | Error _ as error -> Lwt.return error
  | Ok all_users ->
    let%bind all_follows =
      match viewer_id with
      | None -> Lwt.return (Ok [])
      | Some viewer_id ->
        run ~conn User_queries.follows_for_authors { viewer_id; author_ids }
    in
    (match all_follows with
     | Error _ as error -> Lwt.return error
     | Ok all_follows ->
       let%bind all_tags = run ~conn Article_queries.tags_by_article_ids article_ids in
       (match all_tags with
        | Error _ as error -> Lwt.return error
        | Ok all_tags ->
          let%bind all_article_tags =
            run ~conn Article_queries.article_tags_by_article_ids article_ids
          in
          (match all_article_tags with
           | Error _ as error -> Lwt.return error
           | Ok all_article_tags ->
             let%map all_favorites =
               run ~conn Article_queries.favorites_by_article_ids article_ids
             in
             Result.bind all_favorites ~f:(fun all_favorites ->
               List.map
                 rows
                 ~f:
                   (article_of_row
                      ~viewer_id
                      ~all_users
                      ~all_follows
                      ~all_tags
                      ~all_article_tags
                      ~all_favorites)
               |> Result.all))))
;;

let read_article ~conn ~viewer_id slug =
  let%bind found = run ~conn Article_queries.by_slug slug in
  match found with
  | Error _ as error -> Lwt.return error
  | Ok None -> Lwt.return (Ok None)
  | Ok (Some row) ->
    let%map hydrated = hydrate_articles ~conn ~viewer_id [ row ] in
    Result.map hydrated ~f:List.hd_exn |> Result.map ~f:Option.some
;;

let constraint_is_unique = function
  | Adapter.Constraint_violation { kind = Adapter.Unique; _ } -> true
  | _ -> false
;;
