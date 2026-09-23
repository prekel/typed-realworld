open! Base
open Repository_support
open Lwt.Let_syntax

type nonrec 'a io = 'a io
type nonrec connection = connection

let page ~conn ~viewer_id ~filters ~followed_by pagination =
  let%bind rows =
    run
      ~conn
      Article_queries.page
      { Article_queries.Page.filters; followed_by; page = pagination }
  in
  match rows with
  | Error _ as error -> Lwt.return error
  | Ok rows ->
    let%bind count =
      run ~conn Article_queries.count { Article_queries.Count.filters; followed_by }
    in
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
let ensure_tag ~conn name = run ~conn Article_queries.upsert_tag name

let rec sync_tags ~conn ~article_id names index =
  match names with
  | [] -> Lwt.return (Ok ())
  | name :: rest ->
    let%bind tag = ensure_tag ~conn name in
    (match tag with
     | Error _ as error -> Lwt.return error
     | Ok tag ->
       let input : Article_queries.Attach_tag.t =
         { article_id; tag_id = tag.id; position = index }
       in
       let%bind inserted = run_unit ~conn Article_queries.attach_tag input in
       (match inserted with
        | Error _ as error -> Lwt.return error
        | Ok () -> sync_tags ~conn ~article_id rest (index + 1)))
;;

let normalize_tags tags =
  List.fold tags ~init:[] ~f:(fun unique tag ->
    if List.mem unique tag ~equal:Domain.Article.Tag.equal then
      unique
    else
      unique @ [ tag ])
;;

let create ~conn ~author_id ~slug ~now (article : Domain.Article.create) =
  let input : Article_queries.Create_article.t =
    { author_id
    ; slug
    ; title = article.title
    ; description = article.description
    ; body = article.body
    ; now
    }
  in
  let%bind inserted = run ~conn Article_queries.create_article input in
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
       let%map reread =
         read_article
           ~conn
           ~viewer_id:(Some author_id)
           (Domain.Article.Slug.of_string_exn row.slug)
       in
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
    let%bind raw = run ~conn Article_queries.by_slug slug in
    (match raw with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok None -> Lwt.return (Error `Not_found)
     | Ok (Some raw)
       when not (Int64.equal raw.author_id (Domain.User.Id.to_int64 author_id)) ->
       Lwt.return (Error `Forbidden)
     | Ok (Some raw) ->
       let title = Option.value changes.title ~default:raw.title in
       let description = Option.value changes.description ~default:raw.description in
       let body = Option.value changes.body ~default:raw.body in
       let slug' =
         Option.value new_slug ~default:(Domain.Article.Slug.of_string_exn raw.slug)
       in
       let input : Article_queries.Update_article.t =
         { id = raw.id; slug = slug'; title; description; body; now }
       in
       let%bind changed = run_unit ~conn Article_queries.update_article input in
       (match changed with
        | Error error -> Lwt.return (Error (`Persistence error))
        | Ok () ->
          let%bind tag_changed =
            match changes.tag_list with
            | None -> Lwt.return (Ok ())
            | Some names ->
              let%bind removed = run_unit ~conn Article_queries.clear_tags raw.id in
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
  let%bind raw = run ~conn Article_queries.by_slug slug in
  match raw with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some raw) when not (Int64.equal raw.author_id (Domain.User.Id.to_int64 author_id))
    -> Lwt.return (Error `Forbidden)
  | Ok (Some raw) ->
    let%map deleted = run_unit ~conn Article_queries.delete_article raw.id in
    (match deleted with
     | Ok () -> Ok ()
     | Error error -> Error (`Persistence error))
;;

let alter_favorite ~conn ~add ~user_id ~slug =
  let%bind raw = run ~conn Article_queries.by_slug slug in
  match raw with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some raw) ->
    let input : Article_queries.Add_favorite.t = { user_id; article_id = raw.id } in
    let%bind changed =
      if add then
        run_unit ~conn Article_queries.add_favorite input
      else
        run_unit ~conn Article_queries.remove_favorite input
    in
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
