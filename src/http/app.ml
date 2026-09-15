open! Base
open Typed_endpoint

module Make
    (Backend : Backend.S with type 'a io = 'a Lwt.t)
    (Users : Realworld_application.User_service.S)
    (Articles :
       Realworld_application.Article_service.S with type database = Users.database)
    (Comments :
       Realworld_application.Comment_service.S with type database = Users.database) =
struct
  module Endpoint = Make (Backend)
  module Users_controller = User_controller.Make (Backend) (Users)
  module Articles_controller = Article_controller.Make (Backend) (Articles)
  module Comments_controller = Comment_controller.Make (Backend) (Comments)

  let compile ~database ~issue ~verify =
    let dependencies : Users.database Controller_context.dependencies =
      { database; issue; verify }
    in
    Endpoint.compile_exn
      ([ Users_controller.group dependencies; Comments_controller.group dependencies ]
       @ Articles_controller.groups dependencies)
  ;;
end
