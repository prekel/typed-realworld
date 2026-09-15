open! Base

type 'a io = 'a Lwt.t
type connection = Caqti_lwt.connection
type t

val create : Uri.t -> (t, Realworld_application.Persistence_error.t) Result.t Lwt.t
val disconnect : t -> unit Lwt.t

include
  Realworld_application.Database.S
  with type 'a io := 'a io
   and type t := t
   and type connection := connection
