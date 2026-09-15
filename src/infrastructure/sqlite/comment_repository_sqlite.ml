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
        { id = int_of_id row.id
        ; created_at = row.created_at
        ; updated_at = row.updated_at
        ; body = row.body
        ; author = profile_of_user ~viewer_id ~follows:all_follows author
        }
;;

let list ~conn ~viewer_id ~slug =
  let%bind article = article_by_slug ~conn slug in
  match article with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Article_not_found)
  | Ok (Some article) ->
    let%bind all_comments = comments ~conn in
    (match all_comments with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok all_comments ->
       let%bind all_users = users ~conn in
       (match all_users with
        | Error error -> Lwt.return (Error (`Persistence error))
        | Ok all_users ->
          let%bind all_follows = follows ~conn in
          (match all_follows with
           | Error error -> Lwt.return (Error (`Persistence error))
           | Ok all_follows ->
             let listed =
               all_comments
               |> List.filter ~f:(fun comment ->
                 Int64.equal comment.Comments.article_id article.id)
               |> List.sort ~compare:(fun left right ->
                 let order =
                   Ptime.compare left.Comments.created_at right.Comments.created_at
                 in
                 if Int.equal order 0 then
                   Int64.compare left.Comments.id right.Comments.id
                 else
                   order)
               |> List.map ~f:(comment_of_row ~viewer_id ~all_users ~all_follows)
               |> Result.all
             in
             Lwt.return (Result.map_error listed ~f:(fun error -> `Persistence error)))))
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
       let%bind all_users = users ~conn in
       (match all_users with
        | Error error -> Lwt.return (Error (`Persistence error))
        | Ok all_users ->
          let%map all_follows = follows ~conn in
          (match all_follows with
           | Error error -> Error (`Persistence error)
           | Ok all_follows ->
             (match
                comment_of_row ~viewer_id:(Some author_id) ~all_users ~all_follows row
              with
              | Ok comment -> Ok comment
              | Error error -> Error (`Persistence error)))))
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
       when not (Int64.equal comment.Comments.author_id (id_of_int author_id)) ->
       Lwt.return (Error `Forbidden)
     | Ok (Some comment) ->
       let command = Comment_queries.delete comment.id in
       let%map deleted = execute_unit ~conn command in
       (match deleted with
        | Ok () -> Ok ()
        | Error error -> Error (`Persistence error)))
;;
