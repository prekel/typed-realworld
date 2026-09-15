open! Base

module User = struct
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

  let empty_update =
    { email = None; username = None; password = None; bio = None; image = None }
  ;;
end

module Profile = struct
  type t =
    { username : string
    ; bio : string option
    ; image : string option
    ; following : bool
    }
end

module Article = struct
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
    Buffer.contents buffer
  ;;
end

module Comment = struct
  type id = int

  type t =
    { id : id
    ; created_at : Ptime.t
    ; updated_at : Ptime.t
    ; body : string
    ; author : Profile.t
    }
end

module Page = struct
  type t =
    { limit : int
    ; offset : int
    }

  let create ?(limit = 20) ?(offset = 0) () =
    if limit < 0 then
      Error "limit must be non-negative"
    else if offset < 0 then
      Error "offset must be non-negative"
    else
      Ok { limit; offset }
  ;;

  let default = { limit = 20; offset = 0 }
end
