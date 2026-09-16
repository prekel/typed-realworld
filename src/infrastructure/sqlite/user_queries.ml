open! Base
open Typed_sql
open Infix
module User = Realworld_domain.Domain.User
module Users = Schema.Users
module Follows = Schema.Follows

let all_rows () = Query.(from Users.table |> select Users.projection)
let all_follows () = Query.(from Follows.table |> select Follows.projection)

let rows_by_ids ids =
  Query.(
    from Users.table
    |> where (fun user -> Expr.in_ (Users.id user) ids)
    |> select Users.projection)
;;

let follows_for_authors ~viewer_id author_ids =
  Query.(
    from Follows.table
    |> where (fun follow ->
      Follows.follower_id follow
      =$ User.Id.to_int64 viewer_id
      &&. Expr.in_ (Follows.followed_id follow) author_ids)
    |> select Follows.projection)
;;

let projection reference =
  Projection.map (Users.projection reference) ~f:(fun row ->
    User.
      { id = User.Id.of_int64_exn row.id
      ; email = row.email
      ; username = User.Username.of_string_exn row.username
      ; password_hash = row.password_hash
      ; bio = row.bio
      ; image = row.image
      })
;;

let by_id id =
  Query.(
    from Users.table
    |> where (fun user -> Users.id user =$ User.Id.to_int64 id)
    |> select projection)
;;

let by_email email =
  Query.(
    from Users.table |> where (fun user -> Users.email user =$ email) |> select projection)
;;

let by_username username =
  Query.(
    from Users.table
    |> where (fun user -> Users.username user =$ User.Username.to_string username)
    |> select Users.projection)
;;

let insert ~email ~username ~password_hash =
  Insert.(
    into Users.table
    |> set Users.email_column email
    |> set Users.username_column (User.Username.to_string username)
    |> set Users.password_hash_column password_hash
    |> set Users.bio_column None
    |> set Users.image_column None
    |> returning Users.projection)
;;

let update ~id ~email ~username ~password_hash ~bio ~image =
  Update.(
    table Users.table
    |> set Users.email_column email
    |> set Users.username_column (User.Username.to_string username)
    |> set Users.password_hash_column password_hash
    |> set Users.bio_column bio
    |> set Users.image_column image
    |> where (fun user -> Users.id user =$ User.Id.to_int64 id)
    |> returning Users.projection)
;;

let follow ~follower_id ~followed_id =
  Insert.(
    into Follows.table
    |> set Follows.follower_id_column (User.Id.to_int64 follower_id)
    |> set Follows.followed_id_column (User.Id.to_int64 followed_id)
    |> on_conflict_do_nothing
    |> command)
;;

let unfollow ~follower_id ~followed_id =
  Delete.(
    from Follows.table
    |> where (fun follow ->
      Follows.follower_id follow
      =$ User.Id.to_int64 follower_id
      &&. (Follows.followed_id follow =$ User.Id.to_int64 followed_id))
    |> command)
;;
