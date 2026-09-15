open! Base
module Domain = Realworld_domain.Domain

module type S = sig
  val issue : user_id:Domain.User.id -> string
  val verify : string -> Domain.User.id option
end
