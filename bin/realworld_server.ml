open! Base
module Application = Realworld_application
module Database = Realworld_sqlite.Database_sqlite_lwt
module Jwt = Realworld_security.Jwt_hs256

module Clock = struct
  let now () = Ptime_clock.now ()
end

module Users =
  Application.User_service.Make (Database) (Realworld_sqlite.User_repository_sqlite)
    (Realworld_security.Password_scrypt)

module Articles =
  Application.Article_service.Make (Database) (Realworld_sqlite.Article_repository_sqlite)
    (Clock)

module Comments =
  Application.Comment_service.Make (Database) (Realworld_sqlite.Comment_repository_sqlite)
    (Clock)

module Http = Realworld_http.App.Make (Typed_endpoint_opium) (Users) (Articles) (Comments)

let getenv_or_default name default = Stdlib.Sys.getenv_opt name |> Option.value ~default

let database_url () =
  getenv_or_default "REALWORLD_DATABASE_URL" "sqlite3:realworld.sqlite3"
;;

let port () = getenv_or_default "REALWORLD_PORT" "3000" |> Int.of_string

let jwt_secret () =
  getenv_or_default "REALWORLD_JWT_SECRET" "typed-realworld-development-secret"
;;

let () =
  Mirage_crypto_rng_unix.use_default ();
  let secret = jwt_secret () in
  if String.equal secret "typed-realworld-development-secret" then
    Stdlib.prerr_endline "REALWORLD_JWT_SECRET is not set; using the development secret.";
  let module Token = (val Jwt.create ~secret) in
  match Lwt_main.run (Database.create (Uri.of_string (database_url ()))) with
  | Error error ->
    Stdlib.failwith
      ("cannot connect to SQLite: " ^ Application.Persistence_error.public_message error)
  | Ok database ->
    Stdlib.at_exit (fun () -> Lwt_main.run (Database.disconnect database));
    Http.compile ~database ~issue:Token.issue ~verify:Token.verify
    |> Http.Endpoint.Compiled.app
    |> fun routes ->
    Typed_endpoint_opium.mount routes Opium.Std.App.empty
    |> Opium.Std.App.port (port ())
    |> Opium.Std.App.run_command
;;
