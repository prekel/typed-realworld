open! Base
open Repository_support
open Lwt.Let_syntax

type nonrec 'a io = 'a io
type nonrec connection = connection

let article_by_slug ~conn slug = Comment_queries.article_by_slug slug |> fetch_opt ~conn

let comment_of_row ~viewer_id ~all_users ~all_follows row =
  match find_user_row all_users row.Comments.author_id with
  | None -> Error (Persistence_error.of_string "comment author is missing")
  | Some author ->
    Ok
      Domain.Comment.
        { id = Id.of_int64_exn row.id
        ; created_at = row.created_at
        ; updated_at = row.updated_at
        ; body = row.body
        ; author = profile_of_user ~viewer_id ~follows:all_follows author
        }
;;

let hydrate_comments ~conn ~viewer_id rows =
  let author_ids =
    rows
    |> List.map ~f:(fun row -> row.Comments.author_id)
    |> List.dedup_and_sort ~compare:Int64.compare
  in
  let%bind found_users = fetch ~conn (User_queries.rows_by_ids author_ids) in
  match found_users with
  | Error _ as error -> Lwt.return error
  | Ok all_users ->
    let%bind all_follows =
      match viewer_id with
      | None -> Lwt.return (Ok [])
      | Some viewer_id ->
        fetch ~conn (User_queries.follows_for_authors ~viewer_id author_ids)
    in
    (match all_follows with
     | Error _ as error -> Lwt.return error
     | Ok all_follows ->
       let hydrated =
         rows
         |> List.map ~f:(comment_of_row ~viewer_id ~all_users ~all_follows)
         |> Result.all
       in
       Lwt.return hydrated)
;;

let list ~conn ~viewer_id ~slug =
  let%bind article = article_by_slug ~conn slug in
  match article with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Article_not_found)
  | Ok (Some article) ->
    let%bind listed = Comment_queries.by_article article.id |> fetch ~conn in
    (match listed with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok rows ->
       let%map hydrated = hydrate_comments ~conn ~viewer_id rows in
       Result.map_error hydrated ~f:(fun error -> `Persistence error))
;;

let create ~conn ~author_id ~slug ~body ~now =
  let%bind article = article_by_slug ~conn slug in
  match article with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Article_not_found)
  | Ok (Some article) ->
    let insert = Comment_queries.insert ~article_id:article.id ~author_id ~body ~now in
    let%bind inserted = fetch_one ~conn insert in
    (match inserted with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok row ->
       let%map hydrated = hydrate_comments ~conn ~viewer_id:(Some author_id) [ row ] in
       Result.map hydrated ~f:List.hd_exn
       |> Result.map_error ~f:(fun error -> `Persistence error))
;;

let delete ~conn ~author_id ~slug ~comment_id =
  let%bind article = article_by_slug ~conn slug in
  match article with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Article_not_found)
  | Ok (Some article) ->
    let%bind found =
      Comment_queries.by_article_and_id ~article_id:article.id ~comment_id
      |> fetch_opt ~conn
    in
    (match found with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok None -> Lwt.return (Error `Comment_not_found)
     | Ok (Some comment)
       when not
              (Int64.equal comment.Comments.author_id (Domain.User.Id.to_int64 author_id))
       -> Lwt.return (Error `Forbidden)
     | Ok (Some comment) ->
       let command = Comment_queries.delete comment_id in
       let%map deleted = execute_unit ~conn command in
       (match deleted with
        | Ok () -> Ok ()
        | Error error -> Error (`Persistence error)))
;;
