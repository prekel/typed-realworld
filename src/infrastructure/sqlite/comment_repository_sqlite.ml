open! Base
open Repository_support
open Lwt.Let_syntax

type nonrec 'a io = 'a io
type nonrec connection = connection

let article_by_slug ~conn slug = run ~conn Comment_queries.Article_by_slug.statement slug

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
  let%bind found_users = run ~conn User_queries.Rows_by_ids.statement author_ids in
  match found_users with
  | Error _ as error -> Lwt.return error
  | Ok all_users ->
    let%bind all_follows =
      match viewer_id with
      | None -> Lwt.return (Ok [])
      | Some viewer_id ->
        run ~conn User_queries.Follows_for_authors.statement { viewer_id; author_ids }
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
    let%bind listed = run ~conn Comment_queries.By_article.statement article.id in
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
    let input : Comment_queries.Create_comment.Input.t =
      { article_id = article.id; author_id; body; now }
    in
    let%bind inserted = run ~conn Comment_queries.Create_comment.statement input in
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
      run
        ~conn
        Comment_queries.By_article_and_id.statement
        { article_id = article.id; comment_id }
    in
    (match found with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok None -> Lwt.return (Error `Comment_not_found)
     | Ok (Some comment)
       when not
              (Int64.equal comment.Comments.author_id (Domain.User.Id.to_int64 author_id))
       -> Lwt.return (Error `Forbidden)
     | Ok (Some comment) ->
       let%map deleted =
         run_unit ~conn Comment_queries.Delete_comment.statement comment_id
       in
       (match deleted with
        | Ok () -> Ok ()
        | Error error -> Error (`Persistence error)))
;;
