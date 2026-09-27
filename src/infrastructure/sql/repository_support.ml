open! Base
open Typed_sql
open Infix
open Lwt.Let_syntax
module Application = Realworld_application
module Domain = Realworld_domain.Domain
module Persistence_error = Application.Persistence_error
module Schema = Schema
module Users = Schema.Users
module Articles = Schema.Articles
module Tags = Schema.Tags
module Article_tags = Schema.Article_tags
module Favorites = Schema.Favorites
module Follows = Schema.Follows
module Comments = Schema.Comments
module Adapter = Typed_sql_caqti_lwt

type 'a io = 'a Lwt.t
type connection = Caqti_lwt.connection

let persistence error = Persistence_error.of_string (Adapter.error_to_string error)
let run_raw ~conn statement input = Adapter.run ~conn statement input

let run ~conn statement input =
  let%map result = run_raw ~conn statement input in
  Result.map_error result ~f:persistence
;;

let run_unit ~conn statement input =
  let%map result = run ~conn statement input in
  Result.map result ~f:(fun _ -> ())
;;

let direct sql =
  Caqti.Template.Request.create
    Caqti.Template.Request.Direct
    Caqti.Template.Request_type.Infix.(
      Caqti.Template.Row_type.unit -->. Caqti.Template.Row_type.unit)
    (fun _ -> Caqti.Template.Query.parse sql)
;;

let savepoint = direct "SAVEPOINT realworld_unique_mutation"
let rollback_to_savepoint = direct "ROLLBACK TO SAVEPOINT realworld_unique_mutation"
let release_savepoint = direct "RELEASE SAVEPOINT realworld_unique_mutation"

let with_unique_savepoint ~conn ~f =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let%bind started = Connection.exec savepoint () in
  match started with
  | Error error -> Lwt.return (Error (Adapter.Caqti error))
  | Ok () ->
    let%bind result = f () in
    let%bind recovered =
      match result with
      | Ok _ -> Lwt.return (Ok ())
      | Error _ -> Connection.exec rollback_to_savepoint ()
    in
    (match recovered with
     | Error error -> Lwt.return (Error (Adapter.Caqti error))
     | Ok () ->
       let%map released = Connection.exec release_savepoint () in
       (match released with
        | Error error -> Error (Adapter.Caqti error)
        | Ok () -> result))
;;

let profile_of_user ~viewer_id ~follows (user : Domain.User.t) =
  let following =
    Option.value_map viewer_id ~default:false ~f:(fun viewer_id ->
      List.exists follows ~f:(fun follow ->
        Int64.equal follow.Follows.follower_id (Domain.User.Id.to_int64 viewer_id)
        && Int64.equal follow.Follows.followed_id (Domain.User.Id.to_int64 user.id)))
  in
  Domain.Profile.
    { username = user.username; bio = user.bio; image = user.image; following }
;;

let tags ~conn = run ~conn Article_queries.all_tags ()

let find_user_row rows id =
  List.find rows ~f:(fun (user : Domain.User.t) ->
    Int64.equal (Domain.User.Id.to_int64 user.id) id)
;;

let constraint_is_unique = function
  | Adapter.Constraint_violation { kind = Adapter.Unique; _ } -> true
  | _ -> false
;;
