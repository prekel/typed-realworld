open! Base
open Opium.Std
module Application = Realworld_application
module Database = Realworld_sqlite.Database_sqlite_lwt
module Jwt = Realworld_security.Jwt_hs256

module Cors = struct
  let headers =
    [ "Access-Control-Allow-Origin", "*"
    ; "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS"
    ; "Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-Id"
    ; "Access-Control-Expose-Headers", "X-Request-Id"
    ; "Access-Control-Max-Age", "86400"
    ]
  ;;

  let add_headers response =
    let headers =
      List.fold headers ~init:(Response.headers response) ~f:(fun headers (name, value) ->
        Cohttp.Header.replace headers name value)
    in
    { response with Response.headers }
  ;;

  let middleware =
    let filter handler request =
      match Request.meth request with
      | `OPTIONS ->
        Response.create ~code:`No_content ~headers:(Cohttp.Header.of_list headers) ()
        |> Lwt.return
      | _ -> handler request |> Lwt.map add_headers
    in
    Rock.Middleware.create ~name:"cors" ~filter
  ;;
end

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
module Access_log = Realworld_server_support.Access_log

let logger = Access_log.create ()

let request_id_middleware =
  Rock.Middleware.create
    ~name:"realworld-request-id"
    ~filter:(fun next (request : Request.t) ->
      let request_id =
        Access_log.ensure_request_id
          logger
          (Cohttp.Header.get (Request.headers request) "x-request-id")
      in
      let http_request = request.request in
      let http_request =
        { http_request with
          headers = Cohttp.Header.replace http_request.headers "x-request-id" request_id
        }
      in
      let request = { request with request = http_request } in
      let open Lwt.Let_syntax in
      let%map response = next request in
      { response with
        Response.headers =
          Cohttp.Header.replace response.headers "x-request-id" request_id
      })
;;

let access_log_middleware =
  Rock.Middleware.create
    ~name:"realworld-access-log"
    ~filter:(fun next (request : Request.t) ->
      let event =
        Access_log.start
          logger
          ~method_:(Cohttp.Code.string_of_method (Request.meth request))
          ~target:(Uri.to_string (Request.uri request))
          ~request_id:(Cohttp.Header.get (Request.headers request) "x-request-id")
      in
      Lwt.catch
        (fun () ->
           let open Lwt.Let_syntax in
           let%map response = next request in
           Access_log.finish event ~status:(Cohttp.Code.code_of_status response.code);
           response)
        (fun exn ->
           Access_log.fail event exn;
           Lwt.fail exn))
;;

let getenv_or_default name default = Stdlib.Sys.getenv_opt name |> Option.value ~default

let database_url () =
  getenv_or_default "REALWORLD_DATABASE_URL" "sqlite3:realworld.sqlite3"
;;

let port () = getenv_or_default "REALWORLD_PORT" "3000" |> Int.of_string

let jwt_secret () =
  getenv_or_default "REALWORLD_JWT_SECRET" "typed-realworld-development-secret"
;;

let frontend_bundle () =
  getenv_or_default "REALWORLD_FRONTEND_BUNDLE" "frontend/_build/default/main.bc.js"
;;

let frontend_page _request = Opium.Std.respond' (`Html Frontend_page.html)

let frontend_javascript _request =
  let open Lwt.Let_syntax in
  Lwt.catch
    (fun () ->
       let%bind body =
         Lwt_io.with_file ~mode:Lwt_io.Input (frontend_bundle ()) Lwt_io.read
       in
       Opium.Std.respond'
         ~headers:
           (Cohttp.Header.of_list [ "Content-Type", "text/javascript; charset=utf-8" ])
         (`String body))
    (fun _ ->
       Opium.Std.respond'
         ~code:`Service_unavailable
         (`String "frontend bundle is unavailable; run make frontend-build"))
;;

let with_frontend app =
  app
  |> Opium.Std.App.get "/" frontend_page
  |> Opium.Std.App.get "/app" frontend_page
  |> Opium.Std.App.get "/app.js" frontend_javascript
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
    |> with_frontend
    |> Opium.Std.App.middleware request_id_middleware
    |> Opium.Std.App.middleware access_log_middleware
    |> Opium.Std.App.middleware Cors.middleware
    |> Opium.Std.App.port (port ())
    |> Opium.Std.App.run_command
;;
