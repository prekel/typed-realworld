open! Base
open Typed_endpoint

let openapi_config =
  Openapi.Config.v
    ~title:"RealWorld API"
    ~version:"1.0.0"
    ~description:"Typed OCaml implementation of the RealWorld/Conduit API"
    ~servers:[ Openapi.Server.v ~url:"http://localhost:3000" () ]
    ()
;;

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
  open Endpoint

  let openapi_route compiled =
    Unsafe.route ~meth:`GET ~path:"/openapi.json" ~handler:(fun _request ->
      Backend.respond_json (Compiled.openapi ~config:openapi_config compiled))
  ;;

  let docs_page (path, html) =
    Unsafe.route ~meth:`GET ~path ~handler:(fun _request -> Backend.respond_html html)
  ;;

  let compile ~database ~issue ~verify =
    let dependencies : Users.database Controller_context.dependencies =
      { database; issue; verify }
    in
    let api =
      Users_controller.groups dependencies
      @ Comments_controller.groups dependencies
      @ Articles_controller.groups dependencies
    in
    let compiled = Endpoint.compile_exn api in
    let runtime =
      Group.make
        ~description:"Generated API contract and documentation"
        (openapi_route compiled :: List.map Api_docs.pages ~f:docs_page)
    in
    Endpoint.compile_exn (api @ [ runtime ])
  ;;
end
