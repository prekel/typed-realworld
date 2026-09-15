open! Base

module type S = sig
  val now : unit -> Ptime.t
end
