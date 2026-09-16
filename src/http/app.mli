open! Base

(** Compiles the transport-independent controller groups for a concrete Lwt
    backend. Infrastructure implementations are supplied by the composition
    root and never imported by this library. *)
module Make
    (Backend : Typed_endpoint.Backend.S with type 'a io = 'a Lwt.t)
    (Users : Realworld_application.User_service.S)
    (Articles :
       Realworld_application.Article_service.S with type database = Users.database)
    (Comments :
       Realworld_application.Comment_service.S with type database = Users.database) : sig
  module Endpoint : module type of Typed_endpoint.Make (Backend)

  val compile
    :  database:Users.database
    -> issue:(user_id:Realworld_domain.Domain.User.id -> string)
    -> verify:(string -> Realworld_domain.Domain.User.id option)
    -> Endpoint.Compiled.t
end
