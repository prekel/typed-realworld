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

module Make_id () : ID = struct
  type t = int64

  let of_int64 value =
    if Int64.(value > 0L) then
      Some value
    else
      None
  ;;

  let of_string value = Int64.of_string_opt value |> Option.bind ~f:of_int64

  let of_int64_exn value =
    match of_int64 value with
    | Some id -> id
    | None -> invalid_arg "an identifier must be positive"
  ;;

  let to_int64 value = value
  let to_string = Int64.to_string
  let equal = Int64.equal
end

module Patch = struct
  type 'a t =
    | Keep
    | Set of 'a
    | Clear

  let map patch ~f =
    match patch with
    | Keep -> Keep
    | Set value -> Set (f value)
    | Clear -> Clear
  ;;

  let apply patch ~current =
    match patch with
    | Keep -> current
    | Set value -> Some value
    | Clear -> None
  ;;
end

module User = struct
  module Id = Make_id ()

  module Make_identity (Name : sig
      val value : string
    end) : STRING_VALUE = struct
    type t = string

    let of_string value =
      let value = String.strip value |> String.lowercase in
      if
        String.is_empty value
        || not (String.for_all value ~f:(fun character -> Char.to_int character < 128))
      then
        None
      else
        Some value
    ;;

    let of_string_exn value =
      of_string value |> Option.value_exn ~message:("invalid " ^ Name.value)
    ;;

    let to_string value = value
    let equal = String.equal
  end

  module Email : STRING_VALUE = struct
    type t = string

    let of_string value =
      let value = String.strip value |> String.lowercase in
      match String.split value ~on:'@' with
      | [ local; domain ]
        when (not (String.is_empty local))
             && (not (String.is_empty domain))
             && String.for_all value ~f:(fun character ->
               Char.to_int character < 128 && not (Char.is_whitespace character)) ->
        Some value
      | _ -> None
    ;;

    let of_string_exn value = of_string value |> Option.value_exn ~message:"invalid email"
    let to_string value = value
    let equal = String.equal
  end

  module Username = Make_identity (struct
      let value = "username"
    end)

  type id = Id.t

  type t =
    { id : id
    ; email : Email.t
    ; username : Username.t
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

  let empty_update =
    { email = None
    ; username = None
    ; password = None
    ; bio = Patch.Keep
    ; image = Patch.Keep
    }
  ;;
end

module Profile = struct
  type t =
    { username : User.Username.t
    ; bio : string option
    ; image : string option
    ; following : bool
    }
end

module Article = struct
  module Id = Make_id ()

  module Slug : STRING_VALUE = struct
    type t = string

    let valid_character character = Char.is_alphanum character || Char.equal character '-'

    let of_string value =
      if
        String.is_empty value
        || Char.equal value.[0] '-'
        || Char.equal value.[String.length value - 1] '-'
        || (not (String.for_all value ~f:valid_character))
        || String.is_substring value ~substring:"--"
      then
        None
      else
        Some value
    ;;

    let of_string_exn value = of_string value |> Option.value_exn ~message:"invalid slug"
    let to_string value = value
    let equal = String.equal
  end

  module Tag : STRING_VALUE = struct
    type t = string

    let of_string value =
      let value = String.strip value in
      if String.is_empty value then
        None
      else
        Some value
    ;;

    let of_string_exn value = of_string value |> Option.value_exn ~message:"invalid tag"
    let to_string value = value
    let equal = String.equal
  end

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

  let empty_update = { title = None; description = None; body = None; tag_list = None }
  let no_filters = { tag = None; author = None; favorited_by = None }

  let slugify title =
    let buffer = Buffer.create (String.length title) in
    let pending_separator = ref false in
    String.lowercase title
    |> String.iter ~f:(fun character ->
      if Char.is_alphanum character then (
        if !pending_separator && Buffer.length buffer > 0 then
          Buffer.add_char buffer '-';
        pending_separator := false;
        Buffer.add_char buffer character)
      else
        pending_separator := true);
    Buffer.contents buffer |> Slug.of_string
  ;;
end

module Comment = struct
  module Id = Make_id ()

  type id = Id.t

  type t =
    { id : id
    ; created_at : Ptime.t
    ; updated_at : Ptime.t
    ; body : string
    ; author : Profile.t
    }
end

module Page = struct
  module type VALUE = sig
    type t

    val of_int : int -> t option
    val of_string : string -> t option
    val to_int : t -> int
  end

  module Make_value () : VALUE = struct
    type t = int

    let of_int value =
      if value >= 0 then
        Some value
      else
        None
    ;;

    let of_string value = Int.of_string_opt value |> Option.bind ~f:of_int
    let to_int value = value
  end

  module Limit = Make_value ()
  module Offset = Make_value ()

  type t =
    { limit : Limit.t
    ; offset : Offset.t
    }

  let default_limit = Limit.of_int 20 |> Option.value_exn
  let default_offset = Offset.of_int 0 |> Option.value_exn
  let create ?(limit = default_limit) ?(offset = default_offset) () = { limit; offset }
  let limit page = Limit.to_int page.limit
  let offset page = Offset.to_int page.offset
  let default = create ()
end
