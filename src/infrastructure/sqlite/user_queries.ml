open! Base
open Typed_sql
open Infix
module User = Realworld_domain.Domain.User
module Users = Schema.Users
module Follows = Schema.Follows

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

let all_rows : (unit, Users.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Users.table |> select Users.projection))
;;

let%expect_test "all users SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite all_rows);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    |}]
;;

let all_follows : (unit, Follows.t list, Dialect.portable) Statement.t =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(from Follows.table |> select Follows.projection))
;;

let%expect_test "all follows SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite all_follows);
  [%expect
    {|
    SELECT
      t0."follower_id",
      t0."followed_id"
    FROM "follows" AS t0
    |}]
;;

let rows_by_ids =
  Statement.Dynamic.Portable.query_many (fun ids ->
    Query.(
      from Users.table
      |> where (fun user -> Expr.in_ (Users.id user) ids)
      |> select Users.projection))
;;

let%expect_test "users by IDs SQL" =
  Stdlib.print_endline
    (Statement.sql_exn ~dialect:Dialect.Sqlite ~input:[ 7L; 8L ] rows_by_ids);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."id" IN (
        ?1,
        ?2
      ))
    |}]
;;

module Follows_for_authors = struct
  type t =
    { viewer_id : User.Id.t
    ; author_ids : int64 list
    }
  [@@deriving fields ~getters]
end

let follows_for_authors =
  Statement.Dynamic.Portable.query_many (fun (input : Follows_for_authors.t) ->
    Query.(
      from Follows.table
      |> where (fun follow ->
        Follows.follower_id follow
        =$ User.Id.to_int64 input.viewer_id
        &&. Expr.in_ (Follows.followed_id follow) input.author_ids)
      |> select Follows.projection))
;;

let%expect_test "follows for authors SQL" =
  let input : Follows_for_authors.t =
    { viewer_id = User.Id.of_int64_exn 7L; author_ids = [ 8L; 9L ] }
  in
  Stdlib.print_endline
    (Statement.sql_exn ~dialect:Dialect.Sqlite ~input follows_for_authors);
  [%expect
    {|
    SELECT
      t0."follower_id",
      t0."followed_id"
    FROM "follows" AS t0
    WHERE
      (
        (t0."follower_id" = ?1)
        AND (t0."followed_id" IN (
          ?2,
          ?3
        ))
      )
    |}]
;;

let by_id =
  Statement.Portable.query_optional_exn (fun params ->
    let id = params.column Users.id_column ~get:User.Id.to_int64 in
    Query.(
      from Users.table
      |> where (fun user -> Users.id user =. id)
      |> limit_one
      |> select projection))
;;

let%expect_test "user by ID SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite by_id);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."id" = ?1)
    LIMIT 1
    |}]
;;

let by_email =
  Statement.Portable.query_optional_exn (fun params ->
    let email = params.column Users.email_column ~get:Fn.id in
    Query.(
      from Users.table
      |> where (fun user -> Users.email user =. email)
      |> limit_one
      |> select projection))
;;

let%expect_test "user by email SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite by_email);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."email" = ?1)
    LIMIT 1
    |}]
;;

let by_username =
  Statement.Portable.query_optional_exn (fun params ->
    let username = params.column Users.username_column ~get:User.Username.to_string in
    Query.(
      from Users.table
      |> where (fun user -> Users.username user =. username)
      |> limit_one
      |> select Users.projection))
;;

let%expect_test "user by username SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite by_username);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."password_hash",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."username" = ?1)
    LIMIT 1
    |}]
;;

module Create_user = struct
  type t =
    { email : string
    ; username : User.Username.t
    ; password_hash : string
    }
  [@@deriving fields ~getters]

  let username_value input = User.Username.to_string input.username
end

let create_user =
  Statement.Portable.expect_one_exn (fun params ->
    let email = params.column Users.email_column ~get:Create_user.email in
    let username = params.column Users.username_column ~get:Create_user.username_value in
    let password_hash =
      params.column Users.password_hash_column ~get:Create_user.password_hash
    in
    Insert.(
      into Users.table
      |> set_expr Users.email_column email
      |> set_expr Users.username_column username
      |> set_expr Users.password_hash_column password_hash
      |> set Users.bio_column None
      |> set Users.image_column None
      |> returning Users.projection))
;;

let%expect_test "create user SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite create_user);
  [%expect
    {|
    INSERT INTO "users" (
      "email",
      "username",
      "password_hash",
      "bio",
      "image"
    )
    VALUES
      (?1, ?2, ?3, ?4, ?5)
    RETURNING
      "id",
      "email",
      "username",
      "password_hash",
      "bio",
      "image"
    |}]
;;

module Update_user = struct
  type t =
    { id : User.Id.t
    ; email : string
    ; username : User.Username.t
    ; password_hash : string
    ; bio : string option
    ; image : string option
    }
  [@@deriving fields ~getters]

  let id_value input = User.Id.to_int64 input.id
  let username_value input = User.Username.to_string input.username
end

let update_user =
  Statement.Portable.expect_one_exn (fun params ->
    let id = params.column Users.id_column ~get:Update_user.id_value in
    let email = params.column Users.email_column ~get:Update_user.email in
    let username = params.column Users.username_column ~get:Update_user.username_value in
    let password_hash =
      params.column Users.password_hash_column ~get:Update_user.password_hash
    in
    let bio = params.column Users.bio_column ~get:Update_user.bio in
    let image = params.column Users.image_column ~get:Update_user.image in
    Update.(
      table Users.table
      |> set_expr Users.email_column email
      |> set_expr Users.username_column username
      |> set_expr Users.password_hash_column password_hash
      |> set_expr Users.bio_column bio
      |> set_expr Users.image_column image
      |> where (fun user -> Users.id user =. id)
      |> returning Users.projection))
;;

let%expect_test "update user SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite update_user);
  [%expect
    {|
    UPDATE "users"
    SET
      "email" = ?1,
      "username" = ?2,
      "password_hash" = ?3,
      "bio" = ?4,
      "image" = ?5
    WHERE
      ("id" = ?6)
    RETURNING
      "id",
      "email",
      "username",
      "password_hash",
      "bio",
      "image"
    |}]
;;

module Follow_user = struct
  type t =
    { follower_id : User.Id.t
    ; followed_id : User.Id.t
    }
  [@@deriving fields ~getters]

  let follower_id_value input = User.Id.to_int64 input.follower_id
  let followed_id_value input = User.Id.to_int64 input.followed_id
end

let follow_user =
  Statement.Portable.command_exn (fun params ->
    let follower_id =
      params.column Follows.follower_id_column ~get:Follow_user.follower_id_value
    in
    let followed_id =
      params.column Follows.followed_id_column ~get:Follow_user.followed_id_value
    in
    Insert.(
      into Follows.table
      |> set_expr Follows.follower_id_column follower_id
      |> set_expr Follows.followed_id_column followed_id
      |> on_conflict_do_nothing
      |> command))
;;

let%expect_test "follow user SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite follow_user);
  [%expect
    {|
    INSERT INTO "follows" (
      "follower_id",
      "followed_id"
    )
    VALUES
      (?1, ?2)
    ON CONFLICT DO NOTHING
    |}]
;;

let unfollow_user =
  Statement.Portable.command_exn (fun params ->
    let follower_id =
      params.column Follows.follower_id_column ~get:Follow_user.follower_id_value
    in
    let followed_id =
      params.column Follows.followed_id_column ~get:Follow_user.followed_id_value
    in
    Delete.(
      from Follows.table
      |> where (fun follow ->
        Follows.follower_id follow
        =. follower_id
        &&. (Follows.followed_id follow =. followed_id))
      |> command))
;;

let%expect_test "unfollow user SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite unfollow_user);
  [%expect
    {|
    DELETE FROM "follows"
    WHERE
      (
        ("follower_id" = ?1)
        AND ("followed_id" = ?2)
      )
    |}]
;;
