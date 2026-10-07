open! Base
open Typed_sql
open Infix
module User = Realworld_domain.Domain.User
module User_repository = Realworld_application.User_repository
module Users = Schema.Users
module Follows = Schema.Follows

let projection reference =
  let open Projection.Let_syntax in
  let%map id = Projection.expr (Users.id reference)
  and email = Projection.expr (Users.email reference)
  and username = Projection.expr (Users.username reference)
  and bio = Projection.expr (Users.bio reference)
  and image = Projection.expr (Users.image reference) in
  User.
    { id = Id.of_int64_exn id
    ; email = Email.of_string_exn email
    ; username = Username.of_string_exn username
    ; bio
    ; image
    }
;;

let credentials_projection reference =
  let open Projection.Let_syntax in
  let%map user = projection reference
  and password_hash = Projection.expr (Users.password_hash reference) in
  { User_repository.user; password_hash }
;;

let rows_by_ids =
  Statement.choose_dialect
    ~postgresql:
      (Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
         let%map.Parameters ids =
           params.expr (Db_type.Postgresql.array_list Db_type.int64) ~get:Fn.id
         in
         params.query_many
           Query.(
             from Users.table
             |> where (fun user -> Postgresql.Expr.equals_any_list (Users.id user) ids)
             |> select projection)))
    ~sqlite:
      (Statement.Dynamic.query_many ~dialect:Dialect.sqlite (fun ids ->
         Query.(
           from Users.table
           |> where (fun user -> Expr.in_ (Users.id user) ids)
           |> select projection)))
;;

let%expect_test "users by IDs SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite ~input:[ 7L; 8L ] rows_by_ids);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."id" IN (
        ?1,
        ?2
      ))
    |}];
  Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql rows_by_ids);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."id" = ANY(CAST($1 AS bigint[])))
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
  Statement.Dynamic.query_many
    ~dialect:Dialect.portable
    (fun (input : Follows_for_authors.t) ->
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
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite ~input follows_for_authors);
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
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters id = params.column Users.id_column ~get:User.Id.to_int64 in
    params.query_optional
      Query.(
        from Users.table
        |> where (fun user -> Users.id user =. id)
        |> limit_one
        |> select projection))
;;

let%expect_test "user by ID SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite by_id);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."id" = ?1)
    LIMIT 1
    |}]
;;

let credentials_by_email =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters email =
      params.column Users.email_column ~get:User.Email.to_string
    in
    params.query_optional
      Query.(
        from Users.table
        |> where (fun user -> Users.email user =. email)
        |> limit_one
        |> select credentials_projection))
;;

let%expect_test "credentials by email SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite credentials_by_email);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."bio",
      t0."image",
      t0."password_hash"
    FROM "users" AS t0
    WHERE
      (t0."email" = ?1)
    LIMIT 1
    |}]
;;

let by_username =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters username =
      params.column Users.username_column ~get:User.Username.to_string
    in
    params.query_optional
      Query.(
        from Users.table
        |> where (fun user -> Users.username user =. username)
        |> limit_one
        |> select projection))
;;

let%expect_test "user by username SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite by_username);
  [%expect
    {|
    SELECT
      t0."id",
      t0."email",
      t0."username",
      t0."bio",
      t0."image"
    FROM "users" AS t0
    WHERE
      (t0."username" = ?1)
    LIMIT 1
    |}]
;;

module Profile_by_username = struct
  type t =
    { viewer_id : User.Id.t option
    ; username : User.Username.t
    }
  [@@deriving fields ~getters]

  let viewer_id_value input = Option.map input.viewer_id ~f:User.Id.to_int64
  let username_value input = User.Username.to_string input.username
end

let profile_by_username =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters viewer_id =
      params.expr (Db_type.option Db_type.int64) ~get:Profile_by_username.viewer_id_value
    and username =
      params.column Users.username_column ~get:Profile_by_username.username_value
    in
    params.query_optional
      Query.(
        from Users.table
        |> where (fun user -> Users.username user =. username)
        |> limit_one
        |> select (fun user ->
          let followed_id =
            from Follows.table
            |> where (fun follow ->
              Expr.to_nullable (Follows.follower_id follow)
              =. viewer_id
              &&. (Follows.followed_id follow =. Users.id user))
            |> limit_one
            |> select_scalar Follows.followed_id
            |> Expr.scalar_subquery
          in
          let open Projection.Let_syntax in
          let%map username = Projection.expr (Users.username user)
          and bio = Projection.expr (Users.bio user)
          and image = Projection.expr (Users.image user)
          and followed_id = Projection.expr followed_id in
          Realworld_domain.Domain.Profile.
            { username = User.Username.of_string_exn username
            ; bio
            ; image
            ; following = Option.is_some followed_id
            })))
;;

let%expect_test "profile by username SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite profile_by_username);
  [%expect
    {|
    SELECT
      t0."username",
      t0."bio",
      t0."image",
      (
        SELECT
          t1."followed_id"
        FROM "follows" AS t1
        WHERE
          (
            (t1."follower_id" = ?1)
            AND (t1."followed_id" = t0."id")
          )
        LIMIT 1
      )
    FROM "users" AS t0
    WHERE
      (t0."username" = ?2)
    LIMIT 1
    |}]
;;

module Create_user = struct
  type t =
    { email : User.Email.t
    ; username : User.Username.t
    ; password_hash : string
    }
  [@@deriving fields ~getters]

  let email_value input = User.Email.to_string input.email
  let username_value input = User.Username.to_string input.username
end

let create_user =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters email =
      params.column Users.email_column ~get:Create_user.email_value
    and username = params.column Users.username_column ~get:Create_user.username_value
    and password_hash =
      params.column Users.password_hash_column ~get:Create_user.password_hash
    in
    params.expect_one
      Insert.(
        into Users.table
        |> set_expr Users.email_column email
        |> set_expr Users.username_column username
        |> set_expr Users.password_hash_column password_hash
        |> set Users.bio_column None
        |> set Users.image_column None
        |> returning projection))
;;

let%expect_test "create user SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite create_user);
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
      "bio",
      "image"
    |}]
;;

module Update_user = struct
  type t =
    { id : User.Id.t
    ; email : User.Email.t
    ; username : User.Username.t
    ; bio : string option
    ; image : string option
    }
  [@@deriving fields ~getters]

  let id_value input = User.Id.to_int64 input.id
  let email_value input = User.Email.to_string input.email
  let username_value input = User.Username.to_string input.username
end

let update_user =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters id = params.column Users.id_column ~get:Update_user.id_value
    and email = params.column Users.email_column ~get:Update_user.email_value
    and username = params.column Users.username_column ~get:Update_user.username_value
    and bio = params.column Users.bio_column ~get:Update_user.bio
    and image = params.column Users.image_column ~get:Update_user.image in
    params.expect_optional
      Update.(
        table Users.table
        |> set_expr Users.email_column email
        |> set_expr Users.username_column username
        |> set_expr Users.bio_column bio
        |> set_expr Users.image_column image
        |> where (fun user -> Users.id user =. id)
        |> returning projection))
;;

let%expect_test "update user SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite update_user);
  [%expect
    {|
    UPDATE "users"
    SET
      "email" = ?1,
      "username" = ?2,
      "bio" = ?3,
      "image" = ?4
    WHERE
      ("id" = ?5)
    RETURNING
      "id",
      "email",
      "username",
      "bio",
      "image"
    |}]
;;

module Update_password = struct
  type t =
    { id : User.Id.t
    ; password_hash : string
    }
  [@@deriving fields ~getters]

  let id_value input = User.Id.to_int64 input.id
end

let update_password =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters id = params.column Users.id_column ~get:Update_password.id_value
    and password_hash =
      params.column Users.password_hash_column ~get:Update_password.password_hash
    in
    params.command
      Update.(
        table Users.table
        |> set_expr Users.password_hash_column password_hash
        |> where (fun user -> Users.id user =. id)
        |> command))
;;

let%expect_test "update password SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite update_password);
  [%expect
    {|
    UPDATE "users"
    SET
      "password_hash" = ?1
    WHERE
      ("id" = ?2)
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
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters follower_id =
      params.column Follows.follower_id_column ~get:Follow_user.follower_id_value
    and followed_id =
      params.column Follows.followed_id_column ~get:Follow_user.followed_id_value
    in
    params.command
      Insert.(
        into Follows.table
        |> set_expr Follows.follower_id_column follower_id
        |> set_expr Follows.followed_id_column followed_id
        |> on_conflict_do_nothing
        |> command))
;;

let%expect_test "follow user SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite follow_user);
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
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters follower_id =
      params.column Follows.follower_id_column ~get:Follow_user.follower_id_value
    and followed_id =
      params.column Follows.followed_id_column ~get:Follow_user.followed_id_value
    in
    params.command
      Delete.(
        from Follows.table
        |> where (fun follow ->
          Follows.follower_id follow
          =. follower_id
          &&. (Follows.followed_id follow =. followed_id))
        |> command))
;;

let%expect_test "unfollow user SQL" =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Sqlite unfollow_user);
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
