open! Base

module Server =
  Realworld_server_support.Server_main.Make (Realworld_sqlite.Database_sqlite_lwt)

let () =
  Server.run
    ~backend_name:"SQLite"
    ~default_database_url:(Some "sqlite3:realworld.sqlite3")
    ()
;;
