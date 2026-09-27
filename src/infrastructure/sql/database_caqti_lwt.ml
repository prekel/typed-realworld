open! Base
module Persistence_error = Realworld_application.Persistence_error

module type Config = sig
  val schemes : string list
  val max_pool_size : int
  val post_connect : Caqti_lwt.connection -> (unit, Caqti.Error.t) Result.t Lwt.t
end

module Make (Config : Config) = struct
  type 'a io = 'a Lwt.t
  type connection = Caqti_lwt.connection
  type t = (connection, Caqti.Error.t) Caqti_lwt_unix.Pool.t

  let persistence_of_caqti error = Persistence_error.of_string (Caqti.Error.show error)

  let create uri =
    let scheme = Uri.scheme uri |> Option.value ~default:"" in
    if not (List.mem Config.schemes scheme ~equal:String.equal) then
      Lwt.return
        (Error (Persistence_error.of_string ("unexpected database URL scheme: " ^ scheme)))
    else (
      let pool_config =
        Caqti.Pool.Config.create
          ~max_size:Config.max_pool_size
          ~max_idle_size:Config.max_pool_size
          ()
      in
      match
        Caqti_lwt_unix.connect_pool ~pool_config ~post_connect:Config.post_connect uri
      with
      | Error error -> Lwt.return (Error (persistence_of_caqti error))
      | Ok pool -> Lwt.return (Ok pool))
  ;;

  let disconnect = Caqti_lwt_unix.Pool.drain

  let with_connection database ~on_error ~f =
    let open Lwt.Let_syntax in
    let%map result =
      Caqti_lwt_unix.Pool.use
        (fun conn ->
           let%map result = f ~conn in
           Ok result)
        database
    in
    match result with
    | Ok result -> result
    | Error error -> Error (on_error (persistence_of_caqti error))
  ;;

  let transaction database ~on_error ~f =
    let run conn =
      let module Connection = (val conn : Caqti_lwt.CONNECTION) in
      let open Lwt.Let_syntax in
      let%bind started = Connection.start () in
      match started with
      | Error error -> Lwt.return (Error error)
      | Ok () ->
        Lwt.try_bind
          (fun () -> f ~conn)
          (fun result ->
             let%bind finished =
               match result with
               | Ok _ -> Connection.commit ()
               | Error _ -> Connection.rollback ()
             in
             match finished with
             | Ok () -> Lwt.return (Ok result)
             | Error error -> Lwt.return (Error error))
          (fun exception_ ->
             let%bind rolled_back = Connection.rollback () in
             match rolled_back with
             | Ok () -> Lwt.fail exception_
             | Error error -> Lwt.fail (Caqti.Error.Exn error))
    in
    let open Lwt.Let_syntax in
    let%map result = Caqti_lwt_unix.Pool.use run database in
    match result with
    | Ok result -> result
    | Error error -> Error (on_error (persistence_of_caqti error))
  ;;
end
