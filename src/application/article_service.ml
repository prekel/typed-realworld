open! Base
module Domain = Realworld_domain.Domain

module type S = sig
  type database

  val list
    :  database:database
    -> viewer_id:Domain.User.id option
    -> filters:Domain.Article.filters
    -> page:Domain.Page.t
    -> (Article_repository.page, Persistence_error.t) Result.t Lwt.t

  val feed
    :  database:database
    -> viewer_id:Domain.User.id
    -> page:Domain.Page.t
    -> (Article_repository.page, Persistence_error.t) Result.t Lwt.t

  val find
    :  database:database
    -> viewer_id:Domain.User.id option
    -> slug:Domain.Article.Slug.t
    -> (Domain.Article.t option, Persistence_error.t) Result.t Lwt.t

  val create
    :  database:database
    -> author_id:Domain.User.id
    -> Domain.Article.create
    -> ( Domain.Article.t
         , [ `Validation of Validation.t | `Persistence of Persistence_error.t ] )
         Result.t
         Lwt.t

  val update
    :  database:database
    -> author_id:Domain.User.id
    -> slug:Domain.Article.Slug.t
    -> Domain.Article.update
    -> ( Domain.Article.t
         , [ `Forbidden
           | `Not_found
           | `Validation of Validation.t
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         Lwt.t

  val delete
    :  database:database
    -> author_id:Domain.User.id
    -> slug:Domain.Article.Slug.t
    -> (unit, [ `Forbidden | `Not_found | `Persistence of Persistence_error.t ]) Result.t
         Lwt.t

  val favorite
    :  database:database
    -> user_id:Domain.User.id
    -> slug:Domain.Article.Slug.t
    -> (Domain.Article.t, [ `Not_found | `Persistence of Persistence_error.t ]) Result.t
         Lwt.t

  val unfavorite
    :  database:database
    -> user_id:Domain.User.id
    -> slug:Domain.Article.Slug.t
    -> (Domain.Article.t, [ `Not_found | `Persistence of Persistence_error.t ]) Result.t
         Lwt.t

  val tags : database:database -> (string list, Persistence_error.t) Result.t Lwt.t
end

module Make
    (Database : Database.S with type 'a io = 'a Lwt.t)
    (Articles :
       Article_repository.S
       with type 'a io = 'a Lwt.t
        and type connection = Database.connection)
    (Clock : Clock.S) =
struct
  type database = Database.t

  let list ~database ~viewer_id ~filters ~page =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Articles.list ~conn ~viewer_id ~filters ~page)
  ;;

  let feed ~database ~viewer_id ~page =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Articles.feed ~conn ~viewer_id ~page)
  ;;

  let find ~database ~viewer_id ~slug =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Articles.find ~conn ~viewer_id ~slug)
  ;;

  let slug_base title =
    match Domain.Article.slugify title with
    | None -> Domain.Article.Slug.of_string_exn "article"
    | Some value -> value
  ;;

  let candidate base attempt =
    if Int.equal attempt 1 then
      base
    else
      Domain.Article.Slug.of_string_exn
        (Domain.Article.Slug.to_string base ^ "-" ^ Int.to_string attempt)
  ;;

  let create ~database ~author_id article =
    match Validation.article_create article with
    | Error errors -> Lwt.return (Error (`Validation errors))
    | Ok article ->
      let base = slug_base article.title in
      let rec attempt index =
        if index > 1000 then
          Lwt.return
            (Error
               (`Persistence
                   (Persistence_error.of_string "could not allocate article slug")))
        else
          Lwt.bind
            (Database.transaction
               database
               ~on_error:(fun error -> `Persistence error)
               ~f:(fun ~conn ->
                 Articles.create
                   ~conn
                   ~author_id
                   ~slug:(candidate base index)
                   ~now:(Clock.now ())
                   article))
            (function
              | Error `Slug_taken -> attempt (index + 1)
              | Ok value -> Lwt.return (Ok value)
              | Error (`Persistence error) -> Lwt.return (Error (`Persistence error)))
      in
      attempt 1
  ;;

  let update ~database ~author_id ~slug changes =
    match Validation.article_update changes with
    | Error errors -> Lwt.return (Error (`Validation errors))
    | Ok changes ->
      let new_slug = Option.map changes.title ~f:slug_base in
      Database.transaction
        database
        ~on_error:(fun error -> `Persistence error)
        ~f:(fun ~conn ->
          let open Lwt.Let_syntax in
          let%map updated =
            Articles.update ~conn ~author_id ~slug ~new_slug ~now:(Clock.now ()) changes
          in
          match updated with
          | Ok article -> Ok article
          | Error `Forbidden -> Error `Forbidden
          | Error `Not_found -> Error `Not_found
          | Error `Slug_taken ->
            Error (`Persistence (Persistence_error.of_string "article slug conflict"))
          | Error (`Persistence error) -> Error (`Persistence error))
  ;;

  let delete ~database ~author_id ~slug =
    Database.transaction
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn -> Articles.delete ~conn ~author_id ~slug)
  ;;

  let favorite ~database ~user_id ~slug =
    Database.transaction
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn -> Articles.favorite ~conn ~user_id ~slug)
  ;;

  let unfavorite ~database ~user_id ~slug =
    Database.transaction
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn -> Articles.unfavorite ~conn ~user_id ~slug)
  ;;

  let tags ~database =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Articles.tags ~conn)
  ;;
end
