open! Base
module Domain = Realworld_domain.Domain

module type S = sig
  type 'a io
  type connection

  val list
    :  conn:connection
    -> viewer_id:Domain.User.id option
    -> slug:Domain.Article.Slug.t
    -> ( Domain.Comment.t list
         , [ `Article_not_found | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val create
    :  conn:connection
    -> author_id:Domain.User.id
    -> slug:Domain.Article.Slug.t
    -> body:string
    -> now:Ptime.t
    -> ( Domain.Comment.t
         , [ `Article_not_found | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val delete
    :  conn:connection
    -> author_id:Domain.User.id
    -> slug:Domain.Article.Slug.t
    -> comment_id:Domain.Comment.id
    -> ( unit
         , [ `Article_not_found
           | `Comment_not_found
           | `Forbidden
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         io
end
