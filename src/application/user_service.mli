open! Base
module Domain = Realworld_domain.Domain

(** User use cases. The service owns validation, password hashing and
    transaction boundaries; HTTP concerns stay in the controller. *)
module type S = sig
  type database

  val register
    :  database:database
    -> Domain.User.registration
    -> ( Domain.User.t
         , [ `Email_taken
           | `Username_taken
           | `Validation of Validation.t
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         Lwt.t

  val login
    :  database:database
    -> email:string
    -> password:string
    -> ( Domain.User.t
         , [ `Invalid_credentials | `Persistence of Persistence_error.t ] )
         Result.t
         Lwt.t

  val current
    :  database:database
    -> Domain.User.id
    -> (Domain.User.t, [ `Unauthorized | `Persistence of Persistence_error.t ]) Result.t
         Lwt.t

  val update
    :  database:database
    -> user_id:Domain.User.id
    -> Domain.User.update
    -> ( Domain.User.t
         , [ `Email_taken
           | `Username_taken
           | `Unauthorized
           | `Validation of Validation.t
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         Lwt.t

  val profile
    :  database:database
    -> viewer_id:Domain.User.id option
    -> username:Domain.User.Username.t
    -> (Domain.Profile.t option, Persistence_error.t) Result.t Lwt.t

  val follow
    :  database:database
    -> follower_id:Domain.User.id
    -> username:Domain.User.Username.t
    -> ( Domain.Profile.t
         , [ `Cannot_follow_self | `Not_found | `Persistence of Persistence_error.t ] )
         Result.t
         Lwt.t

  val unfollow
    :  database:database
    -> follower_id:Domain.User.id
    -> username:Domain.User.Username.t
    -> (Domain.Profile.t, [ `Not_found | `Persistence of Persistence_error.t ]) Result.t
         Lwt.t
end

module Make
    (Database : Database.S with type 'a io = 'a Lwt.t)
    (Users :
       User_repository.S
       with type 'a io = 'a Lwt.t
        and type connection = Database.connection)
    (Hasher : Password_hasher.S) : S with type database = Database.t
