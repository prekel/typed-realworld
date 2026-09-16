open! Base
module Domain = Realworld_domain.Domain

(** Comment use cases and their authorization-aware failures. *)
module type S = sig
  type database

  val list
    :  database:database
    -> viewer_id:Domain.User.id option
    -> slug:Domain.Article.Slug.t
    -> ( Domain.Comment.t list
         , [ `Article_not_found | `Persistence of Persistence_error.t ] )
         Result.t
         Lwt.t

  val create
    :  database:database
    -> author_id:Domain.User.id
    -> slug:Domain.Article.Slug.t
    -> body:string
    -> ( Domain.Comment.t
         , [ `Article_not_found
           | `Validation of Validation.t
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         Lwt.t

  val delete
    :  database:database
    -> author_id:Domain.User.id
    -> slug:Domain.Article.Slug.t
    -> comment_id:Domain.Comment.id
    -> ( unit
         , [ `Article_not_found
           | `Comment_not_found
           | `Forbidden
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         Lwt.t
end

module Make
    (Database : Database.S with type 'a io = 'a Lwt.t)
    (Comments :
       Comment_repository.S
       with type 'a io = 'a Lwt.t
        and type connection = Database.connection)
    (Clock : Clock.S) : S with type database = Database.t
