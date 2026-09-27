open! Base

module Server =
  Realworld_server_support.Server_main.Make (Realworld_postgres.Database_postgres_lwt)

let () = Server.run ~backend_name:"PostgreSQL" ~default_database_url:None ()
