open! Base
open Repository_support
open Lwt.Let_syntax

type nonrec 'a io = 'a io
type nonrec connection = connection

let page ~conn ~viewer_id ~filters ~followed_by pagination =
  let%bind rows =
    Article_queries.page ~filters ~followed_by ~page:pagination |> fetch ~conn
  in
  match rows with
  | Error _ as error -> Lwt.return error
  | Ok rows ->
    let%bind count = Article_queries.count ~filters ~followed_by |> fetch_one ~conn in
    (match count with
     | Error _ as error -> Lwt.return error
     | Ok count ->
       let%map hydrated = hydrate_articles ~conn ~viewer_id rows in
       Result.map hydrated ~f:(fun articles ->
         { Application.Article_repository.articles; count = Int64.to_int_exn count }))
;;

let list ~conn ~viewer_id ~filters ~page:pagination =
  page ~conn ~viewer_id ~filters ~followed_by:None pagination
;;

let feed ~conn ~viewer_id ~page:pagination =
  page
    ~conn
    ~viewer_id:(Some viewer_id)
    ~filters:Domain.Article.no_filters
    ~followed_by:(Some viewer_id)
    pagination
;;

let find ~conn ~viewer_id ~slug = read_article ~conn ~viewer_id slug
let tag_by_name ~conn name = Article_queries.tag_by_name name |> fetch_opt ~conn

let ensure_tag ~conn name =
  let%bind found = tag_by_name ~conn name in
  match found with
  | Error _ as error -> Lwt.return error
  | Ok (Some tag) -> Lwt.return (Ok tag)
  | Ok None ->
    let insert = Article_queries.insert_tag name in
    let%map inserted = fetch_one ~conn insert in
    (match inserted with
     | Ok tag -> Ok tag
     | Error error -> Error error)
;;

let rec sync_tags ~conn ~article_id names index =
  match names with
  | [] -> Lwt.return (Ok ())
  | name :: rest ->
    let%bind tag = ensure_tag ~conn name in
    (match tag with
     | Error _ as error -> Lwt.return error
     | Ok tag ->
       let command =
         Article_queries.attach_tag ~article_id ~tag_id:tag.id ~position:index
       in
       let%bind inserted = execute_unit ~conn command in
       (match inserted with
        | Error _ as error -> Lwt.return error
        | Ok () -> sync_tags ~conn ~article_id rest (index + 1)))
;;

let normalize_tags tags =
  List.fold tags ~init:[] ~f:(fun unique tag ->
    if List.mem unique tag ~equal:String.equal then
      unique
    else
      unique @ [ tag ])
;;

let create ~conn ~author_id ~slug ~now (article : Domain.Article.create) =
  let insert = Article_queries.insert ~author_id ~slug ~now article in
  let%bind inserted = fetch_one ~conn insert in
  match inserted with
  | Error error
    when String.is_substring (Persistence_error.to_string error) ~substring:"constraint"
    -> Lwt.return (Error `Slug_taken)
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok row ->
    let%bind synced =
      sync_tags ~conn ~article_id:row.id (normalize_tags article.tag_list) 0
    in
    (match synced with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok () ->
       let%map reread = read_article ~conn ~viewer_id:(Some author_id) row.slug in
       (match reread with
        | Ok (Some article) -> Ok article
        | Ok None ->
          Error (`Persistence (Persistence_error.of_string "created article is missing"))
        | Error error -> Error (`Persistence error)))
;;

let update ~conn ~author_id ~slug ~new_slug ~now (changes : Domain.Article.update) =
  let%bind current = read_article ~conn ~viewer_id:(Some author_id) slug in
  match current with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some _) ->
    let%bind raw = Article_queries.by_slug slug |> fetch_one ~conn in
    (match raw with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok raw when not (Int64.equal raw.author_id (id_of_int author_id)) ->
       Lwt.return (Error `Forbidden)
     | Ok raw ->
       let title = Option.value changes.title ~default:raw.title in
       let description = Option.value changes.description ~default:raw.description in
       let body = Option.value changes.body ~default:raw.body in
       let slug' = Option.value new_slug ~default:raw.slug in
       let update =
         Article_queries.update ~id:raw.id ~slug:slug' ~title ~description ~body ~now
       in
       let%bind changed = execute_unit ~conn update in
       (match changed with
        | Error error -> Lwt.return (Error (`Persistence error))
        | Ok () ->
          let%bind tag_changed =
            match changes.tag_list with
            | None -> Lwt.return (Ok ())
            | Some None ->
              Lwt.return (Error (Persistence_error.of_string "tagList must not be null"))
            | Some (Some names) ->
              let delete = Article_queries.clear_tags raw.id in
              let%bind removed = execute_unit ~conn delete in
              (match removed with
               | Error _ as error -> Lwt.return error
               | Ok () -> sync_tags ~conn ~article_id:raw.id (normalize_tags names) 0)
          in
          (match tag_changed with
           | Error error -> Lwt.return (Error (`Persistence error))
           | Ok () ->
             let%map reread = read_article ~conn ~viewer_id:(Some author_id) slug' in
             (match reread with
              | Ok (Some article) -> Ok article
              | Ok None ->
                Error
                  (`Persistence (Persistence_error.of_string "updated article is missing"))
              | Error error -> Error (`Persistence error)))))
;;

let delete ~conn ~author_id ~slug =
  let%bind raw = Article_queries.by_slug slug |> fetch_opt ~conn in
  match raw with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some raw) when not (Int64.equal raw.author_id (id_of_int author_id)) ->
    Lwt.return (Error `Forbidden)
  | Ok (Some raw) ->
    let command = Article_queries.delete raw.id in
    let%map deleted = execute_unit ~conn command in
    (match deleted with
     | Ok () -> Ok ()
     | Error error -> Error (`Persistence error))
;;

let alter_favorite ~conn ~add ~user_id ~slug =
  let%bind raw = Article_queries.by_slug slug |> fetch_opt ~conn in
  match raw with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some raw) ->
    let command =
      if add then
        Article_queries.add_favorite ~user_id ~article_id:raw.id
      else
        Article_queries.remove_favorite ~user_id ~article_id:raw.id
    in
    let%bind changed = execute_unit ~conn command in
    (match changed with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok () ->
       let%map reread = read_article ~conn ~viewer_id:(Some user_id) slug in
       (match reread with
        | Ok (Some article) -> Ok article
        | Ok None ->
          Error (`Persistence (Persistence_error.of_string "article is missing"))
        | Error error -> Error (`Persistence error)))
;;

let favorite ~conn ~user_id ~slug = alter_favorite ~conn ~add:true ~user_id ~slug
let unfavorite ~conn ~user_id ~slug = alter_favorite ~conn ~add:false ~user_id ~slug

let tags ~conn =
  let%map all_tags = tags ~conn in
  Result.map all_tags ~f:(fun tags -> List.map tags ~f:(fun tag -> tag.Tags.name))
;;
