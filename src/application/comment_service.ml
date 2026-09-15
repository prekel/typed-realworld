open! Base
module Domain = Realworld_domain.Domain

module type S = sig
  type database

  val list
    :  database:database
    -> viewer_id:Domain.User.id option
    -> slug:string
    -> ( Domain.Comment.t list
         , [ `Article_not_found | `Persistence of Persistence_error.t ] )
         Result.t
         Lwt.t

  val create
    :  database:database
    -> author_id:Domain.User.id
    -> slug:string
    -> body:string
    -> ( Domain.Comment.t
         , [ `Article_not_found
           | `Validation of Validation.t
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         Lwt.t

  val delete
    :  database:database
    -> author_id:Domain.User.id
    -> slug:string
    -> comment_id:Domain.Comment.id
    -> ( unit
         , [ `Article_not_found
           | `Comment_not_found
           | `Forbidden
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         Lwt.t
end

module Make
    (Database : Database.S with type 'a io = 'a Lwt.t)
    (Comments :
       Comment_repository.S
       with type 'a io = 'a Lwt.t
        and type connection = Database.connection)
    (Clock : Clock.S) =
struct
  type database = Database.t

  let list ~database ~viewer_id ~slug =
    Database.with_connection
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn -> Comments.list ~conn ~viewer_id ~slug)
  ;;

  let create ~database ~author_id ~slug ~body =
    if Validation.blank body then
      Lwt.return (Error (`Validation (Validation.field "body" "can't be blank")))
    else
      Database.transaction
        database
        ~on_error:(fun error -> `Persistence error)
        ~f:(fun ~conn ->
          let open Lwt.Let_syntax in
          let%map created =
            Comments.create ~conn ~author_id ~slug ~body ~now:(Clock.now ())
          in
          match created with
          | Ok comment -> Ok comment
          | Error `Article_not_found -> Error `Article_not_found
          | Error (`Persistence error) -> Error (`Persistence error))
  ;;

  let delete ~database ~author_id ~slug ~comment_id =
    Database.transaction
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn -> Comments.delete ~conn ~author_id ~slug ~comment_id)
  ;;
end
