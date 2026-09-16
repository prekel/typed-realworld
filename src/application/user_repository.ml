open! Base
module Domain = Realworld_domain.Domain

type changes =
  { email : string option
  ; username : Domain.User.Username.t option
  ; password_hash : string option
  ; bio : string Domain.Patch.t
  ; image : string Domain.Patch.t
  }

module type S = sig
  type 'a io
  type connection

  val create
    :  conn:connection
    -> email:string
    -> username:Domain.User.Username.t
    -> password_hash:string
    -> ( Domain.User.t
         , [ `Email_taken | `Username_taken | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val find_by_id
    :  conn:connection
    -> Domain.User.id
    -> (Domain.User.t option, Persistence_error.t) Result.t io

  val find_by_email
    :  conn:connection
    -> string
    -> (Domain.User.t option, Persistence_error.t) Result.t io

  val update
    :  conn:connection
    -> id:Domain.User.id
    -> changes
    -> ( Domain.User.t
         , [ `Email_taken
           | `Username_taken
           | `Not_found
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         io

  val profile
    :  conn:connection
    -> viewer_id:Domain.User.id option
    -> username:Domain.User.Username.t
    -> (Domain.Profile.t option, Persistence_error.t) Result.t io

  val follow
    :  conn:connection
    -> follower_id:Domain.User.id
    -> username:Domain.User.Username.t
    -> ( Domain.Profile.t
         , [ `Cannot_follow_self | `Not_found | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val unfollow
    :  conn:connection
    -> follower_id:Domain.User.id
    -> username:Domain.User.Username.t
    -> (Domain.Profile.t, [ `Not_found | `Persistence of Persistence_error.t ]) Result.t
         io
end
