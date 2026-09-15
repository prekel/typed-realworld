open! Base

module type S = sig
  val hash : string -> (string, string) Result.t
  val verify : encoded:string -> string -> bool
end
