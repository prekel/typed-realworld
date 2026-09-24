open! Base

type t = (string * string list) list

val field : string -> string -> t
val combine : t list -> t
val is_empty : t -> bool
val blank : string -> bool
val normalized_identity : string -> string -> (string, t) Result.t
val email : string -> (Realworld_domain.Domain.User.Email.t, t) Result.t

val normalized_optional_text
  :  string Realworld_domain.Domain.Patch.t
  -> string Realworld_domain.Domain.Patch.t

val password : string -> (string, t) Result.t

val article_create
  :  Realworld_domain.Domain.Article.create
  -> (Realworld_domain.Domain.Article.create, t) Result.t

val article_update
  :  Realworld_domain.Domain.Article.update
  -> (Realworld_domain.Domain.Article.update, t) Result.t
