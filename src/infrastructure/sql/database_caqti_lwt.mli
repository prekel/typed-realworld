open! Base

(** Backend configuration for the shared Caqti Lwt pool implementation. *)
module type Config = sig
  (** URI schemes accepted by this database module. *)
  val schemes : string list

  (** Maximum number of pooled connections. *)
  val max_pool_size : int

  (** Connection initialization, for example enabling SQLite foreign keys. *)
  val post_connect : Caqti_lwt.connection -> (unit, Caqti.Error.t) Result.t Lwt.t
end

(** Pool, connection scope and transaction implementation shared by the
    SQLite and PostgreSQL adapters. *)
module Make (Config : Config) : sig
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
end
