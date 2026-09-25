open! Base

(** JSONL access log event builder for the HTTP server. *)
type t

type request

val create
  :  ?now:(unit -> float)
  -> ?write:(string -> unit)
  -> ?fresh_id:(unit -> string)
  -> unit
  -> t

val ensure_request_id : t -> string option -> string
val start : t -> method_:string -> target:string -> request_id:string option -> request
val request_id : request -> string
val finish : request -> status:int -> unit
val fail : request -> exn -> unit
