open! Base
open Repository_support
open Lwt.Let_syntax

type nonrec 'a io = 'a io
type nonrec connection = connection

let find_by_id ~conn id = run ~conn User_queries.by_id id

let find_credentials_by_email ~conn email =
  run ~conn User_queries.credentials_by_email email
;;

let find_by_username ~conn username = run ~conn User_queries.by_username username

let different_user except_id (user : Domain.User.t) =
  Option.value_map except_id ~default:true ~f:(fun id ->
    not (Domain.User.Id.equal id user.id))
;;

let identity_conflict ~conn ?except_id ~email ~username () =
  let%bind by_email = find_credentials_by_email ~conn email in
  match by_email with
  | Error error -> Lwt.return (Error error)
  | Ok (Some credentials) when different_user except_id credentials.user ->
    Lwt.return (Ok (Some `Email_taken))
  | Ok None | Ok (Some _) ->
    let%map by_username = find_by_username ~conn username in
    Result.map by_username ~f:(function
      | Some user when different_user except_id user -> Some `Username_taken
      | None | Some _ -> None)
;;

let classify_unique ~conn ?except_id ~email ~username adapter_error =
  let%map conflict = identity_conflict ~conn ?except_id ~email ~username () in
  match conflict with
  | Error error -> Error (`Persistence error)
  | Ok (Some conflict) -> Error conflict
  | Ok None -> Error (`Persistence (persistence adapter_error))
;;

let create ~conn ~email ~username ~password_hash =
  let input : User_queries.Create_user.t = { email; username; password_hash } in
  let%bind inserted =
    with_unique_savepoint ~conn ~f:(fun () ->
      run_raw ~conn User_queries.create_user input)
  in
  match inserted with
  | Ok user -> Lwt.return (Ok user)
  | Error error when constraint_is_unique error ->
    classify_unique ~conn ~email ~username error
  | Error error -> Lwt.return (Error (`Persistence (persistence error)))
;;

let update ~conn ~id (changes : Application.User_repository.changes) =
  let%bind current = find_by_id ~conn id in
  match current with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some current) ->
    let email = Option.value changes.email ~default:current.email in
    let username = Option.value changes.username ~default:current.username in
    let bio = Domain.Patch.apply changes.bio ~current:current.bio in
    let image = Domain.Patch.apply changes.image ~current:current.image in
    let input : User_queries.Update_user.t = { id; email; username; bio; image } in
    let%bind updated =
      with_unique_savepoint ~conn ~f:(fun () ->
        run_raw ~conn User_queries.update_user input)
    in
    (match updated with
     | Error error when constraint_is_unique error ->
       classify_unique ~conn ~except_id:id ~email ~username error
     | Error error -> Lwt.return (Error (`Persistence (persistence error)))
     | Ok None -> Lwt.return (Error `Not_found)
     | Ok (Some user) ->
       (match changes.password_hash with
        | None -> Lwt.return (Ok user)
        | Some password_hash ->
          let input : User_queries.Update_password.t = { id; password_hash } in
          let%map changed = run_unit ~conn User_queries.update_password input in
          Result.map changed ~f:(fun () -> user)
          |> Result.map_error ~f:(fun error -> `Persistence error)))
;;

let profile ~conn ~viewer_id ~username =
  let input : User_queries.Profile_by_username.t = { viewer_id; username } in
  run ~conn User_queries.profile_by_username input
;;

let profile_of_user ~following (user : Domain.User.t) =
  Domain.Profile.
    { username = user.username; bio = user.bio; image = user.image; following }
;;

let follow ~conn ~follower_id ~username =
  let%bind target = find_by_username ~conn username in
  match target with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some target) when Domain.User.Id.equal target.id follower_id ->
    Lwt.return (Error `Cannot_follow_self)
  | Ok (Some target) ->
    let input : User_queries.Follow_user.t = { follower_id; followed_id = target.id } in
    let%map inserted = run_unit ~conn User_queries.follow_user input in
    Result.map inserted ~f:(fun () -> profile_of_user ~following:true target)
    |> Result.map_error ~f:(fun error -> `Persistence error)
;;

let unfollow ~conn ~follower_id ~username =
  let%bind target = find_by_username ~conn username in
  match target with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some target) ->
    let input : User_queries.Follow_user.t = { follower_id; followed_id = target.id } in
    let%map deleted = run_unit ~conn User_queries.unfollow_user input in
    Result.map deleted ~f:(fun () -> profile_of_user ~following:false target)
    |> Result.map_error ~f:(fun error -> `Persistence error)
;;
