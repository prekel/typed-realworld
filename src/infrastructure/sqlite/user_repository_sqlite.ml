open! Base
open Repository_support
open Lwt.Let_syntax

type nonrec 'a io = 'a io
type nonrec connection = connection

let find_by_id ~conn id = run ~conn User_queries.by_id id
let find_by_email ~conn email = run ~conn User_queries.by_email email
let find_by_username ~conn username = run ~conn User_queries.by_username username

let create ~conn ~email ~username ~password_hash =
  let%bind email_exists = find_by_email ~conn email in
  match email_exists with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok (Some _) -> Lwt.return (Error `Email_taken)
  | Ok None ->
    let%bind username_exists = find_by_username ~conn username in
    (match username_exists with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok (Some _) -> Lwt.return (Error `Username_taken)
     | Ok None ->
       let input : User_queries.Create_user.t = { email; username; password_hash } in
       let%map inserted = run ~conn User_queries.create_user input in
       (match inserted with
        | Ok row -> Ok (user_of_row row)
        | Error error -> Error (`Persistence error)))
;;

let update ~conn ~id (changes : Application.User_repository.changes) =
  let%bind current = find_by_id ~conn id in
  match current with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some current) ->
    let email = Option.value changes.email ~default:current.email in
    let username = Option.value changes.username ~default:current.username in
    let%bind duplicate_email =
      if String.equal email current.email then
        Lwt.return (Ok None)
      else
        find_by_email ~conn email
    in
    (match duplicate_email with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok (Some _) -> Lwt.return (Error `Email_taken)
     | Ok None ->
       let%bind duplicate_username =
         if Domain.User.Username.equal username current.username then
           Lwt.return (Ok None)
         else
           find_by_username ~conn username
       in
       (match duplicate_username with
        | Error error -> Lwt.return (Error (`Persistence error))
        | Ok (Some _) -> Lwt.return (Error `Username_taken)
        | Ok None ->
          let password_hash =
            Option.value changes.password_hash ~default:current.password_hash
          in
          let bio = Domain.Patch.apply changes.bio ~current:current.bio in
          let image = Domain.Patch.apply changes.image ~current:current.image in
          let input : User_queries.Update_user.t =
            { id; email; username; password_hash; bio; image }
          in
          let%map updated = run ~conn User_queries.update_user input in
          (match updated with
           | Ok row -> Ok (user_of_row row)
           | Error error -> Error (`Persistence error))))
;;

let profile ~conn ~viewer_id ~username =
  let%bind all_users = users ~conn in
  match all_users with
  | Error error -> Lwt.return (Error error)
  | Ok all_users ->
    let%map all_follows = follows ~conn in
    Result.map all_follows ~f:(fun all_follows ->
      List.find all_users ~f:(fun user ->
        String.equal user.Users.username (Domain.User.Username.to_string username))
      |> Option.map ~f:(profile_of_user ~viewer_id ~follows:all_follows))
;;

let follow ~conn ~follower_id ~username =
  let%bind target = find_by_username ~conn username in
  match target with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some target) when Int64.equal target.id (Domain.User.Id.to_int64 follower_id) ->
    Lwt.return (Error `Cannot_follow_self)
  | Ok (Some target) ->
    let followed_id = Domain.User.Id.of_int64_exn target.id in
    let input : User_queries.Follow_user.t = { follower_id; followed_id } in
    let%bind inserted = run_unit ~conn User_queries.follow_user input in
    (match inserted with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok () ->
       let%map all_follows = follows ~conn in
       Result.map all_follows ~f:(fun all_follows ->
         profile_of_user ~viewer_id:(Some follower_id) ~follows:all_follows target)
       |> Result.map_error ~f:(fun error -> `Persistence error))
;;

let unfollow ~conn ~follower_id ~username =
  let%bind target = find_by_username ~conn username in
  match target with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some target) ->
    let followed_id = Domain.User.Id.of_int64_exn target.id in
    let input : User_queries.Follow_user.t = { follower_id; followed_id } in
    let%bind deleted = run_unit ~conn User_queries.unfollow_user input in
    (match deleted with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok () ->
       let%map all_follows = follows ~conn in
       Result.map all_follows ~f:(fun all_follows ->
         profile_of_user ~viewer_id:(Some follower_id) ~follows:all_follows target)
       |> Result.map_error ~f:(fun error -> `Persistence error))
;;
