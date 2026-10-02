open! Base

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

module Registration_request : sig
  type t

  include Typed_endpoint.Request_payload.S with type t := t

  val to_domain : t -> Realworld_domain.Domain.User.registration
end

module Login_request : sig
  type t

  include Typed_endpoint.Request_payload.S with type t := t

  val email : t -> string
  val password : t -> string
end

module User_update_request : sig
  type t

  include Typed_endpoint.Request_payload.S with type t := t

  val to_domain : t -> (Realworld_domain.Domain.User.update, string * string) Result.t
end

module Article_create_request : sig
  type t

  include Typed_endpoint.Request_payload.S with type t := t

  val to_domain : t -> Realworld_domain.Domain.Article.create
end

module Article_update_request : sig
  type t

  include Typed_endpoint.Request_payload.S with type t := t

  val to_domain : t -> (Realworld_domain.Domain.Article.update, unit) Result.t
end

module Comment_create_request : sig
  type t

  include Typed_endpoint.Request_payload.S with type t := t

  val body : t -> string
end
