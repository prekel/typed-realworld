open! Base

module type ID = sig
  type t

  val of_int64 : int64 -> t option
  val of_string : string -> t option
  val of_int64_exn : int64 -> t
  val to_int64 : t -> int64
  val to_string : t -> string
  val equal : t -> t -> bool
end

module type STRING_VALUE = sig
  type t

  val of_string : string -> t option
  val of_string_exn : string -> t
  val to_string : t -> string
  val equal : t -> t -> bool
end

module Patch : sig
  type 'a t =
    | Keep
    | Set of 'a
    | Clear

  val map : 'a t -> f:('a -> 'b) -> 'b t
  val apply : 'a t -> current:'a option -> 'a option
end

module User : sig
  module Id : ID
  module Username : STRING_VALUE

  type id = Id.t

  type t =
    { id : id
    ; email : string
    ; username : Username.t
    ; password_hash : string
    ; bio : string option
    ; image : string option
    }

  type registration =
    { email : string
    ; username : string
    ; password : string
    }

  type update =
    { email : string option
    ; username : string option
    ; password : string option
    ; bio : string Patch.t
    ; image : string Patch.t
    }

  val empty_update : update
end

module Profile : sig
  type t =
    { username : User.Username.t
    ; bio : string option
    ; image : string option
    ; following : bool
    }
end

module Article : sig
  module Id : ID
  module Slug : STRING_VALUE
  module Tag : STRING_VALUE

  type id = Id.t

  type t =
    { id : id
    ; slug : Slug.t
    ; title : string
    ; description : string
    ; body : string
    ; tag_list : Tag.t list
    ; created_at : Ptime.t
    ; updated_at : Ptime.t
    ; favorited : bool
    ; favorites_count : int
    ; author : Profile.t
    }

  type create =
    { title : string
    ; description : string
    ; body : string
    ; tag_list : Tag.t list
    }

  type update =
    { title : string option
    ; description : string option
    ; body : string option
    ; tag_list : Tag.t list option
    }

  type filters =
    { tag : Tag.t option
    ; author : User.Username.t option
    ; favorited_by : User.Username.t option
    }

  val empty_update : update
  val no_filters : filters
  val slugify : string -> Slug.t option
end

module Comment : sig
  module Id : ID

  type id = Id.t

  type t =
    { id : id
    ; created_at : Ptime.t
    ; updated_at : Ptime.t
    ; body : string
    ; author : Profile.t
    }
end

module Page : sig
  module type VALUE = sig
    type t

    val of_int : int -> t option
    val of_string : string -> t option
    val to_int : t -> int
  end

  module Limit : VALUE
  module Offset : VALUE

  type t

  val create : ?limit:Limit.t -> ?offset:Offset.t -> unit -> t
  val limit : t -> int
  val offset : t -> int
  val default : t
end
