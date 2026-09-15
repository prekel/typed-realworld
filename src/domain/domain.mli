open! Base

module User : sig
  type id = int

  type t =
    { id : id
    ; email : string
    ; username : string
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
    ; bio : string option option
    ; image : string option option
    }

  val empty_update : update
end

module Profile : sig
  type t =
    { username : string
    ; bio : string option
    ; image : string option
    ; following : bool
    }
end

module Article : sig
  type id = int

  type t =
    { id : id
    ; slug : string
    ; title : string
    ; description : string
    ; body : string
    ; tag_list : string list
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
    ; tag_list : string list
    }

  type update =
    { title : string option
    ; description : string option
    ; body : string option
    ; tag_list : string list option option
    }

  type filters =
    { tag : string option
    ; author : string option
    ; favorited_by : string option
    }

  val empty_update : update
  val no_filters : filters
  val slugify : string -> string
end

module Comment : sig
  type id = int

  type t =
    { id : id
    ; created_at : Ptime.t
    ; updated_at : Ptime.t
    ; body : string
    ; author : Profile.t
    }
end

module Page : sig
  type t =
    { limit : int
    ; offset : int
    }

  val create : ?limit:int -> ?offset:int -> unit -> (t, string) Result.t
  val default : t
end
