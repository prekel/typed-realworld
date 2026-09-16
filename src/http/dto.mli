open! Base

val errors : (string * string list) list -> Yojson.Safe.t
val user : token:string -> Realworld_domain.Domain.User.t -> Yojson.Safe.t
val profile : Realworld_domain.Domain.Profile.t -> Yojson.Safe.t
val article : include_body:bool -> Realworld_domain.Domain.Article.t -> Yojson.Safe.t
val articles : Realworld_domain.Domain.Article.t list -> count:int -> Yojson.Safe.t
val comment : Realworld_domain.Domain.Comment.t -> Yojson.Safe.t
val comments : Realworld_domain.Domain.Comment.t list -> Yojson.Safe.t
val tags : string list -> Yojson.Safe.t
val object_field : Yojson.Safe.t -> string -> Yojson.Safe.t option
val required_string : Yojson.Safe.t -> string -> (string, string) Result.t
val optional_string : Yojson.Safe.t -> string -> (string option, string) Result.t

val optional_nullable_string
  :  Yojson.Safe.t
  -> string
  -> (string Realworld_domain.Domain.Patch.t, string) Result.t

val optional_string_list
  :  Yojson.Safe.t
  -> string
  -> (string list Realworld_domain.Domain.Patch.t, string) Result.t

module Error_response : sig
  type t

  val make : (string * string list) list -> t

  include Typed_endpoint.Response_payload.S with type t := t
end

module User_response : sig
  type t

  val make : token:string -> Realworld_domain.Domain.User.t -> t

  include Typed_endpoint.Response_payload.S with type t := t
end

module Profile_response : sig
  type t

  val make : Realworld_domain.Domain.Profile.t -> t

  include Typed_endpoint.Response_payload.S with type t := t
end

module Article_response : sig
  type t

  val make : Realworld_domain.Domain.Article.t -> t

  include Typed_endpoint.Response_payload.S with type t := t
end

module Articles_response : sig
  type t

  val make : articles:Realworld_domain.Domain.Article.t list -> count:int -> t

  include Typed_endpoint.Response_payload.S with type t := t
end

module Comment_response : sig
  type t

  val make : Realworld_domain.Domain.Comment.t -> t

  include Typed_endpoint.Response_payload.S with type t := t
end

module Comments_response : sig
  type t

  val make : Realworld_domain.Domain.Comment.t list -> t

  include Typed_endpoint.Response_payload.S with type t := t
end

module Tags_response : sig
  type t

  val make : string list -> t

  include Typed_endpoint.Response_payload.S with type t := t
end

module Registration_request :
  Typed_endpoint.Request_payload.S with type t = Realworld_domain.Domain.User.registration

module Login_request : sig
  type t =
    { email : string
    ; password : string
    }

  include Typed_endpoint.Request_payload.S with type t := t
end

module User_update_request : sig
  type t =
    | Valid of Realworld_domain.Domain.User.update
    | Invalid of string * string

  include Typed_endpoint.Request_payload.S with type t := t
end

module Article_create_request :
  Typed_endpoint.Request_payload.S with type t = Realworld_domain.Domain.Article.create

module Article_update_request : sig
  type t =
    | Valid of Realworld_domain.Domain.Article.update
    | Invalid_tag_list

  include Typed_endpoint.Request_payload.S with type t := t
end

module Comment_create_request : Typed_endpoint.Request_payload.S with type t = string
