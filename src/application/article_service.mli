open! Base
module Domain = Realworld_domain.Domain

(** Article use cases and their domain-level failures. *)
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
    -> slug:string
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
    -> slug:string
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
    -> slug:string
    -> (unit, [ `Forbidden | `Not_found | `Persistence of Persistence_error.t ]) Result.t
         Lwt.t

  val favorite
    :  database:database
    -> user_id:Domain.User.id
    -> slug:string
    -> (Domain.Article.t, [ `Not_found | `Persistence of Persistence_error.t ]) Result.t
         Lwt.t

  val unfavorite
    :  database:database
    -> user_id:Domain.User.id
    -> slug:string
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
    (Clock : Clock.S) : S with type database = Database.t
