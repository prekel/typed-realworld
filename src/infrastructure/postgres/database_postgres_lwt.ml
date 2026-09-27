open! Base

include Realworld_sql.Database_caqti_lwt.Make (struct
    let schemes = [ "postgresql" ]
    let max_pool_size = 10
    let post_connect _ = Lwt.return (Ok ())
  end)
