open! Base
module Domain = Realworld_domain.Domain

type page =
  { articles : Domain.Article.t list
  ; count : int
  }

module type S = sig
  type 'a io
  type connection

  val list
    :  conn:connection
    -> viewer_id:Domain.User.id option
    -> filters:Domain.Article.filters
    -> page:Domain.Page.t
    -> (page, Persistence_error.t) Result.t io

  val feed
    :  conn:connection
    -> viewer_id:Domain.User.id
    -> page:Domain.Page.t
    -> (page, Persistence_error.t) Result.t io

  val find
    :  conn:connection
    -> viewer_id:Domain.User.id option
    -> slug:string
    -> (Domain.Article.t option, Persistence_error.t) Result.t io

  val create
    :  conn:connection
    -> author_id:Domain.User.id
    -> slug:string
    -> now:Ptime.t
    -> Domain.Article.create
    -> (Domain.Article.t, [ `Slug_taken | `Persistence of Persistence_error.t ]) Result.t
         io

  val update
    :  conn:connection
    -> author_id:Domain.User.id
    -> slug:string
    -> new_slug:string option
    -> now:Ptime.t
    -> Domain.Article.update
    -> ( Domain.Article.t
         , [ `Forbidden | `Not_found | `Slug_taken | `Persistence of Persistence_error.t ]
         )
         Result.t
         io

  val delete
    :  conn:connection
    -> author_id:Domain.User.id
    -> slug:string
    -> (unit, [ `Forbidden | `Not_found | `Persistence of Persistence_error.t ]) Result.t
         io

  val favorite
    :  conn:connection
    -> user_id:Domain.User.id
    -> slug:string
    -> (Domain.Article.t, [ `Not_found | `Persistence of Persistence_error.t ]) Result.t
         io

  val unfavorite
    :  conn:connection
    -> user_id:Domain.User.id
    -> slug:string
    -> (Domain.Article.t, [ `Not_found | `Persistence of Persistence_error.t ]) Result.t
         io

  val tags : conn:connection -> (string list, Persistence_error.t) Result.t io
end
