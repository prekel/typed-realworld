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

module All_rows = struct
  module Input = struct
    type t = unit
  end

  let statement =
    Statement.Portable.query_many_exn (fun (_ : (Input.t, _) Statement.parameters) ->
      Query.(from Users.table |> select Users.projection))
  ;;
end

module All_follows = struct
  module Input = struct
    type t = unit
  end

  let statement =
    Statement.Portable.query_many_exn (fun (_ : (Input.t, _) Statement.parameters) ->
      Query.(from Follows.table |> select Follows.projection))
  ;;
end

module Rows_by_ids = struct
  module Input = struct
    type t = int64 list
  end

  let statement =
    Statement.Dynamic.Portable.query_many (fun ids ->
      Query.(
        from Users.table
        |> where (fun user -> Expr.in_ (Users.id user) ids)
        |> select Users.projection))
  ;;
end

module Follows_for_authors = struct
  module Input = struct
    type t =
      { viewer_id : User.Id.t
      ; author_ids : int64 list
      }
    [@@deriving fields ~getters]
  end

  let statement =
    Statement.Dynamic.Portable.query_many (fun (input : Input.t) ->
      Query.(
        from Follows.table
        |> where (fun follow ->
          Follows.follower_id follow
          =$ User.Id.to_int64 input.viewer_id
          &&. Expr.in_ (Follows.followed_id follow) input.author_ids)
        |> select Follows.projection))
  ;;
end

module By_id = struct
  module Input = struct
    type t = User.Id.t
  end

  let statement =
    Statement.Portable.query_optional_exn (fun params ->
      let id = params.column Users.id_column ~get:User.Id.to_int64 in
      Query.(
        from Users.table |> where (fun user -> Users.id user =. id) |> select projection))
  ;;
end

module By_email = struct
  module Input = struct
    type t = string
  end

  let statement =
    Statement.Portable.query_optional_exn (fun params ->
      let email = params.column Users.email_column ~get:Fn.id in
      Query.(
        from Users.table
        |> where (fun user -> Users.email user =. email)
        |> select projection))
  ;;
end

module By_username = struct
  module Input = struct
    type t = User.Username.t
  end

  let statement =
    Statement.Portable.query_optional_exn (fun params ->
      let username = params.column Users.username_column ~get:User.Username.to_string in
      Query.(
        from Users.table
        |> where (fun user -> Users.username user =. username)
        |> select Users.projection))
  ;;
end

module Create_user = struct
  module Input = struct
    type t =
      { email : string
      ; username : User.Username.t
      ; password_hash : string
      }
    [@@deriving fields ~getters]

    let username_value input = User.Username.to_string input.username
  end

  let statement =
    Statement.Portable.query_one_exn (fun params ->
      let email = params.column Users.email_column ~get:Input.email in
      let username = params.column Users.username_column ~get:Input.username_value in
      let password_hash =
        params.column Users.password_hash_column ~get:Input.password_hash
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
end

module Update_user = struct
  module Input = struct
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

  let statement =
    Statement.Portable.query_one_exn (fun params ->
      let id = params.column Users.id_column ~get:Input.id_value in
      let email = params.column Users.email_column ~get:Input.email in
      let username = params.column Users.username_column ~get:Input.username_value in
      let password_hash =
        params.column Users.password_hash_column ~get:Input.password_hash
      in
      let bio = params.column Users.bio_column ~get:Input.bio in
      let image = params.column Users.image_column ~get:Input.image in
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
end

module Follow_user = struct
  module Input = struct
    type t =
      { follower_id : User.Id.t
      ; followed_id : User.Id.t
      }
    [@@deriving fields ~getters]

    let follower_id_value input = User.Id.to_int64 input.follower_id
    let followed_id_value input = User.Id.to_int64 input.followed_id
  end

  let statement =
    Statement.Portable.command_exn (fun params ->
      let follower_id =
        params.column Follows.follower_id_column ~get:Input.follower_id_value
      in
      let followed_id =
        params.column Follows.followed_id_column ~get:Input.followed_id_value
      in
      Insert.(
        into Follows.table
        |> set_expr Follows.follower_id_column follower_id
        |> set_expr Follows.followed_id_column followed_id
        |> on_conflict_do_nothing
        |> command))
  ;;
end

module Unfollow_user = struct
  module Input = Follow_user.Input

  let statement =
    Statement.Portable.command_exn (fun params ->
      let follower_id =
        params.column Follows.follower_id_column ~get:Input.follower_id_value
      in
      let followed_id =
        params.column Follows.followed_id_column ~get:Input.followed_id_value
      in
      Delete.(
        from Follows.table
        |> where (fun follow ->
          Follows.follower_id follow
          =. follower_id
          &&. (Follows.followed_id follow =. followed_id))
        |> command))
  ;;
end
