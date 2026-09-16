open! Base
module Domain = Realworld_domain.Domain

module type S = sig
  type database

  val register
    :  database:database
    -> Domain.User.registration
    -> ( Domain.User.t
         , [ `Email_taken
           | `Username_taken
           | `Validation of Validation.t
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         Lwt.t

  val login
    :  database:database
    -> email:string
    -> password:string
    -> ( Domain.User.t
         , [ `Invalid_credentials | `Persistence of Persistence_error.t ] )
         Result.t
         Lwt.t

  val current
    :  database:database
    -> Domain.User.id
    -> (Domain.User.t, [ `Unauthorized | `Persistence of Persistence_error.t ]) Result.t
         Lwt.t

  val update
    :  database:database
    -> user_id:Domain.User.id
    -> Domain.User.update
    -> ( Domain.User.t
         , [ `Email_taken
           | `Username_taken
           | `Unauthorized
           | `Validation of Validation.t
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         Lwt.t

  val profile
    :  database:database
    -> viewer_id:Domain.User.id option
    -> username:Domain.User.Username.t
    -> (Domain.Profile.t option, Persistence_error.t) Result.t Lwt.t

  val follow
    :  database:database
    -> follower_id:Domain.User.id
    -> username:Domain.User.Username.t
    -> ( Domain.Profile.t
         , [ `Cannot_follow_self | `Not_found | `Persistence of Persistence_error.t ] )
         Result.t
         Lwt.t

  val unfollow
    :  database:database
    -> follower_id:Domain.User.id
    -> username:Domain.User.Username.t
    -> (Domain.Profile.t, [ `Not_found | `Persistence of Persistence_error.t ]) Result.t
         Lwt.t
end

module Make
    (Database : Database.S with type 'a io = 'a Lwt.t)
    (Users :
       User_repository.S
       with type 'a io = 'a Lwt.t
        and type connection = Database.connection)
    (Hasher : Password_hasher.S) =
struct
  type database = Database.t

  let register ~database (registration : Domain.User.registration) =
    match
      ( Validation.normalized_identity "email" registration.email
      , Validation.normalized_identity "username" registration.username
      , Validation.password registration.password )
    with
    | Error errors, _, _ | _, Error errors, _ | _, _, Error errors ->
      Lwt.return (Error (`Validation errors))
    | Ok email, Ok username, Ok password ->
      let username = Domain.User.Username.of_string_exn username in
      (match Hasher.hash password with
       | Error message ->
         Lwt.return (Error (`Persistence (Persistence_error.of_string message)))
       | Ok password_hash ->
         Database.transaction
           database
           ~on_error:(fun error -> `Persistence error)
           ~f:(fun ~conn ->
             let open Lwt.Let_syntax in
             let%map created = Users.create ~conn ~email ~username ~password_hash in
             match created with
             | Ok user -> Ok user
             | Error `Email_taken -> Error `Email_taken
             | Error `Username_taken -> Error `Username_taken
             | Error (`Persistence error) -> Error (`Persistence error)))
  ;;

  let login ~database ~email ~password =
    match Validation.normalized_identity "email" email with
    | Error _ -> Lwt.return (Error `Invalid_credentials)
    | Ok email ->
      Database.with_connection
        database
        ~on_error:(fun error -> `Persistence error)
        ~f:(fun ~conn ->
          let open Lwt.Let_syntax in
          let%map found = Users.find_by_email ~conn email in
          match found with
          | Error error -> Error (`Persistence error)
          | Ok (Some user) when Hasher.verify ~encoded:user.password_hash password ->
            Ok user
          | Ok _ -> Error `Invalid_credentials)
  ;;

  let current ~database user_id =
    Database.with_connection
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn ->
        let open Lwt.Let_syntax in
        let%map found = Users.find_by_id ~conn user_id in
        match found with
        | Ok (Some user) -> Ok user
        | Ok None -> Error `Unauthorized
        | Error error -> Error (`Persistence error))
  ;;

  let update ~database ~user_id (changes : Domain.User.update) =
    let email =
      Option.value_map changes.email ~default:(Ok None) ~f:(fun value ->
        Result.map (Validation.normalized_identity "email" value) ~f:Option.some)
    in
    let username =
      Option.value_map changes.username ~default:(Ok None) ~f:(fun value ->
        Result.map (Validation.normalized_identity "username" value) ~f:(fun value ->
          Some (Domain.User.Username.of_string_exn value)))
    in
    let password =
      Option.value_map changes.password ~default:(Ok None) ~f:(fun value ->
        Result.map (Validation.password value) ~f:Option.some)
    in
    match email, username, password with
    | Error errors, _, _ | _, Error errors, _ | _, _, Error errors ->
      Lwt.return (Error (`Validation errors))
    | Ok email, Ok username, Ok password ->
      let hashed_password =
        match password with
        | None -> Ok None
        | Some value -> Hasher.hash value |> Result.map ~f:Option.some
      in
      (match hashed_password with
       | Error message ->
         Lwt.return (Error (`Persistence (Persistence_error.of_string message)))
       | Ok password_hash ->
         let changes : User_repository.changes =
           { email
           ; username
           ; password_hash
           ; bio = Validation.normalized_optional_text changes.bio
           ; image = Validation.normalized_optional_text changes.image
           }
         in
         Database.transaction
           database
           ~on_error:(fun error -> `Persistence error)
           ~f:(fun ~conn ->
             let open Lwt.Let_syntax in
             let%map updated = Users.update ~conn ~id:user_id changes in
             match updated with
             | Ok user -> Ok user
             | Error `Email_taken -> Error `Email_taken
             | Error `Username_taken -> Error `Username_taken
             | Error `Not_found -> Error `Unauthorized
             | Error (`Persistence error) -> Error (`Persistence error)))
  ;;

  let profile ~database ~viewer_id ~username =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Users.profile ~conn ~viewer_id ~username)
  ;;

  let follow ~database ~follower_id ~username =
    Database.transaction
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn -> Users.follow ~conn ~follower_id ~username)
  ;;

  let unfollow ~database ~follower_id ~username =
    Database.transaction
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn -> Users.unfollow ~conn ~follower_id ~username)
  ;;
end
