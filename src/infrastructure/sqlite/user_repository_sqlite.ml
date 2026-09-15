open! Base
open Repository_support
open Lwt.Let_syntax

type nonrec 'a io = 'a io
type nonrec connection = connection

let find_by_id ~conn id = User_queries.by_id id |> fetch_opt ~conn
let find_by_email ~conn email = User_queries.by_email email |> fetch_opt ~conn
let find_by_username ~conn username = User_queries.by_username username |> fetch_opt ~conn

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
       let insert = User_queries.insert ~email ~username ~password_hash in
       let%map inserted = fetch_one ~conn insert in
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
         if String.equal username current.username then
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
          let bio = Option.value changes.bio ~default:current.bio in
          let image = Option.value changes.image ~default:current.image in
          let update =
            User_queries.update ~id ~email ~username ~password_hash ~bio ~image
          in
          let%map updated = fetch_one ~conn update in
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
      List.find all_users ~f:(fun user -> String.equal user.Users.username username)
      |> Option.map ~f:(profile_of_user ~viewer_id ~follows:all_follows))
;;

let follow ~conn ~follower_id ~username =
  let%bind target = find_by_username ~conn username in
  match target with
  | Error error -> Lwt.return (Error (`Persistence error))
  | Ok None -> Lwt.return (Error `Not_found)
  | Ok (Some target) when Int64.equal target.id (id_of_int follower_id) ->
    Lwt.return (Error `Cannot_follow_self)
  | Ok (Some target) ->
    let command = User_queries.follow ~follower_id ~followed_id:target.id in
    let%bind inserted = execute_unit ~conn command in
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
    let command = User_queries.unfollow ~follower_id ~followed_id:target.id in
    let%bind deleted = execute_unit ~conn command in
    (match deleted with
     | Error error -> Lwt.return (Error (`Persistence error))
     | Ok () ->
       let%map all_follows = follows ~conn in
       Result.map all_follows ~f:(fun all_follows ->
         profile_of_user ~viewer_id:(Some follower_id) ~follows:all_follows target)
       |> Result.map_error ~f:(fun error -> `Persistence error))
;;
