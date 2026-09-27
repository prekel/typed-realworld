open! Base

let direct sql =
  Caqti.Template.Request.create
    Caqti.Template.Request.Direct
    Caqti.Template.Request_type.Infix.(
      Caqti.Template.Row_type.unit -->. Caqti.Template.Row_type.unit)
    (fun _ -> Caqti.Template.Query.parse sql)
;;

let configure conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Connection.exec (direct "PRAGMA foreign_keys = ON") ()
;;

include Realworld_sql.Database_caqti_lwt.Make (struct
    let schemes = [ "sqlite"; "sqlite3" ]
    let max_pool_size = 1
    let post_connect = configure
  end)
